#pragma once
// Firebase Realtime Database sync, so the status page works from any network
// (see cloud/ for the hosted page and the database security rules).
//
//   devices/<id>/status    device -> page  activity, alarm, battery... (+updatedAt)
//   devices/<id>/info      device -> page  name, which channels have credentials
//   devices/<id>/applied   device -> page  settings in use, last error, test reply
//   devices/<id>/control   page -> device  settings {telegramOn,gmailOn,chatIds,emailTo,inactiveMin}, testAt
//
// The device signs in as its own Firebase user (REST, email/password) and only
// makes outgoing HTTPS requests, so it works behind any router or CGNAT.
// Status is sent on change (at most every 2 s; alarms at once) plus a 30 s
// heartbeat; control is polled every 5 s over one kept-alive TLS connection.
// That connection holds the notifier's TlsGate and is closed whenever an
// alert is waiting to be sent (RAM fits one TLS session, see notifier.h).
// Runs in its own task on core 0: no network delay reaches the sensing loop.
#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include "notifier.h"
#include "device_status.h"
#include "cloud_json.h"

#ifndef FIREBASE_API_KEY
#define FIREBASE_API_KEY ""
#endif
#ifndef FIREBASE_DB_URL
#define FIREBASE_DB_URL ""
#endif
#ifndef FIREBASE_DEVICE_EMAIL
#define FIREBASE_DEVICE_EMAIL ""
#endif
#ifndef FIREBASE_DEVICE_PASSWORD
#define FIREBASE_DEVICE_PASSWORD ""
#endif
#ifndef CLOUD_DEVICE_ID
#define CLOUD_DEVICE_ID "baonga-01"
#endif

// HTTPClient::getString() waits for the body with no deadline as long as the
// connection stays open: on a lossy link (seen on the board) the cloud task
// hung in sign-in for minutes. Reads the body (Content-Length or chunked) and
// gives up after timeoutMs; false = incomplete, the caller drops the connection.
// Call collectBodyHeaders() before sending, so the encoding is known.
inline void collectBodyHeaders(HTTPClient &http) {
  static const char *keys[] = {"Transfer-Encoding"};
  http.collectHeaders(keys, 1);
}
inline bool readBody(HTTPClient &http, String &out, uint32_t timeoutMs, size_t maxLen = 8192) {
  out = String();
  NetworkClient *s = http.getStreamPtr();
  if (!s) return false;
  const uint32_t start = millis();
  auto readByte = [&](int &c) {
    while (!s->available()) {
      if (!s->connected() || uint32_t(millis() - start) >= timeoutMs) return false;
      delay(2);
    }
    c = s->read();
    return c >= 0;
  };
  auto readLine = [&](String &line) {
    line = String();
    for (int c; readByte(c);) {
      if (c == '\n') return true;
      if (c != '\r' && line.length() < 32) line += char(c);
    }
    return false;
  };
  const int size = http.getSize();
  bool chunked = false;
  if (size < 0) { // No Content-Length: chunked (Google APIs) or until close.
    String te = http.header("Transfer-Encoding");
    te.toLowerCase();
    chunked = te.indexOf("chunked") >= 0;
  }
  if (!chunked) {
    for (int c; size < 0 || int(out.length()) < size;) {
      if (!readByte(c)) return size < 0 && !s->connected(); // until close: done when closed
      if (out.length() >= maxLen) return false;
      out += char(c);
    }
    return true;
  }
  for (String line;;) {
    if (!readLine(line)) return false;
    const long n = strtol(line.c_str(), nullptr, 16);
    if (n == 0) return true;
    for (long i = 0; i < n; ++i) {
      int c;
      if (!readByte(c) || out.length() >= maxLen) return false;
      out += char(c);
    }
    if (!readLine(line)) return false; // CRLF after the chunk
  }
}

class CloudSync {
 public:
  enum class State : uint8_t { Off, Connecting, Online, AuthError };

  static bool configured() {
    return *FIREBASE_API_KEY && *FIREBASE_DB_URL && *FIREBASE_DEVICE_EMAIL && *FIREBASE_DEVICE_PASSWORD &&
           *CLOUD_DEVICE_ID;
  }
  // Call after notifier.begin() succeeded (Wi-Fi configured).
  bool begin(Notifier &notifier, StatusBoard &board) {
    if (!configured()) return false;
    notifier_ = &notifier;
    board_ = &board;
    snprintf(base_, sizeof(base_), "%s", FIREBASE_DB_URL);
    for (size_t n = strlen(base_); n && base_[n - 1] == '/'; --n) base_[n - 1] = '\0';
    state_ = State::Connecting;
    return xTaskCreatePinnedToCore(taskMain, "cloud", 10240, this, 1, &task_, 0) == pdPASS;
  }
  State state() const { return state_; }
  // Wake the task at once (alert about to go out); no-op before begin().
  void wake() {
    if (task_) xTaskNotifyGive(task_);
  }
  // A fall candidate is under observation: for PREWARM_MS keep the TLS gate, a
  // valid token and the Firebase connection ready, so a confirmed fall can be
  // pushed without a handshake. Sends nothing by itself. Call from the loop.
  void prewarm() {
    prewarmAt_ = millis() | 1; // never 0 (0 = not requested)
    wake();
  }

 private:
  static constexpr uint32_t POLL_MS = 5000, HEARTBEAT_MS = 30000, MIN_STATUS_MS = 2000;
  static constexpr uint32_t TOKEN_MS = 50UL * 60 * 1000; // ID tokens last 60 min
  static constexpr uint32_t AUTH_RETRY_MS = 5UL * 60 * 1000, MAX_BACKOFF_MS = 60000;
  // No reply at all (Wi-Fi/Internet blip): each try already waits up to 10 s
  // for the connection, so retry soon instead of growing to a minute; the
  // page calls the device offline after 75 s without news.
  static constexpr uint32_t NET_MAX_BACKOFF_MS = 8000;
  static constexpr uint32_t PREWARM_MS = 10000;
  static constexpr uint32_t FAST_FLUSH_TIMEOUT_MS = 1500;
  static constexpr uint32_t PREWARM_REPOLL_MS = 1000; // reopen attempts while pre-warming

  Notifier *notifier_ = nullptr;
  StatusBoard *board_ = nullptr;
  TaskHandle_t task_ = nullptr;
  volatile uint32_t prewarmAt_ = 0;
  volatile State state_ = State::Off;
  WiFiClientSecure db_; // Kept alive between database requests.
  HTTPClient http_;
  String response_;
  char base_[128] = "", token_[1600] = "", url_[2048], body_[1024], message_[192];
  bool haveToken_ = false, infoSent_ = false, appliedSent_ = false, controlSeen_ = false;
  bool sentOnce_ = false, cloudKnown_ = false, malformedReported_ = false, holdingTls_ = false;
  bool netError_ = false; // Last failure had no HTTP reply.
  uint32_t wifiUpAt_ = 0;  // for the "synced N ms after Wi-Fi" log
  uint32_t tokenAt_ = 0, polledAt_ = 0, sentAt_ = 0, failAt_ = 0, backoffMs_ = 0;
  uint64_t lastTestAt_ = 0;
  DeviceStatus sent_;
  NotifySettings cloud_; // Last control/settings seen (as stored in the cloud).

  static void taskMain(void *arg) { static_cast<CloudSync *>(arg)->run(); }

  void run() {
    db_.setTimeout(10000);
    db_.setHandshakeTimeout(10);
    http_.setReuse(true);
    http_.setTimeout(10000);
    for (;;) {
      gStageCloud.set("idle");
      ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(250)); // 250 ms tick, or earlier via wake()
      if (WiFi.status() != WL_CONNECTED) {
        wifiUpAt_ = 0;
        releaseTls();
        if (state_ == State::Online) state_ = State::Connecting;
        continue;
      }
      if (notifier_->tls().alertWaiting) { // Alerts first.
        if (holdingTls_ && haveToken_ && db_.connected()) fastFlush();
        releaseTls();
        continue;
      }
      const uint32_t now = millis();
      if (!wifiUpAt_) wifiUpAt_ = now;
      if (backoffMs_ && uint32_t(now - failAt_) < backoffMs_) continue;
      if (!holdingTls_) {
        if (!notifier_->tls().take(0)) continue; // An alert is being sent.
        holdingTls_ = true;
      }
      if (!haveToken_ || uint32_t(now - tokenAt_) >= TOKEN_MS) {
        if (!signIn()) continue;
      }
      bool ok = infoSent_ || (infoSent_ = putInfo());
      if (ok && notifier_->uploadPending()) ok = uploadLocalSettings();
      const bool reopen = prewarming(now) && !db_.connected() && uint32_t(now - polledAt_) >= PREWARM_REPOLL_MS;
      if (ok && (!controlSeen_ || reopen || uint32_t(now - polledAt_) >= POLL_MS)) {
        ok = pollControl();
        if (ok) polledAt_ = now;
      }
      if (ok) ok = sendStatusIfDue(now);
      if (ok) {
        if (state_ != State::Online)
          notifier_->report("[CLOUD] Da dong bo Firebase (thiet bi %s), %lu ms sau khi co Wi-Fi.", CLOUD_DEVICE_ID,
                            (unsigned long)(millis() - wifiUpAt_));
        state_ = State::Online;
        backoffMs_ = 0;
      } else {
        fail(0);
      }
    }
  }

  bool prewarming(uint32_t now) const {
    const uint32_t at = prewarmAt_;
    return at && uint32_t(now - at) < PREWARM_MS;
  }

  // Alert waiting while the Firebase connection is open: put the alarm status
  // there first (one quick request, short timeouts), then the gate goes to the
  // notifier. A failure is not a cloud fault: no backoff, the caller releases.
  void fastFlush() {
    const uint32_t t0 = millis();
    http_.setTimeout(FAST_FLUSH_TIMEOUT_MS);
    db_.setTimeout(FAST_FLUSH_TIMEOUT_MS);
    const bool ok = sendStatusIfDue(t0);
    http_.setTimeout(10000);
    db_.setTimeout(10000);
    if (ok) notifier_->report("[CLOUD] Day nhanh canh bao len Firebase: %lu ms", (unsigned long)(millis() - t0));
  }

  void fail(uint32_t atLeastMs) {
    failAt_ = millis();
    backoffMs_ = backoffMs_ ? backoffMs_ * 2 : 2000;
    const uint32_t cap = netError_ ? NET_MAX_BACKOFF_MS : MAX_BACKOFF_MS;
    if (backoffMs_ > cap) backoffMs_ = cap;
    if (backoffMs_ < atLeastMs) backoffMs_ = atLeastMs;
    if (state_ == State::Online) state_ = State::Connecting;
    releaseTls(); // A half-dead keep-alive connection is reopened next time.
  }

  // Closes the kept-alive connection (frees its ~46 KB) and the TLS gate.
  // Every request runs while holding the gate, so nothing is open otherwise.
  void releaseTls() {
    if (!holdingTls_) return;
    db_.stop();
    holdingTls_ = false;
    notifier_->tls().give();
  }

  // ---- Firebase Auth (REST): email/password -> ID token ----
  bool signIn() {
    const uint32_t t0 = millis();
    gStageCloud.set("signin");
    db_.stop(); // One TLS session at a time keeps the heap comfortable.
    char email[96], password[128];
    jsonEscape(email, sizeof(email), FIREBASE_DEVICE_EMAIL);
    jsonEscape(password, sizeof(password), FIREBASE_DEVICE_PASSWORD);
    snprintf(body_, sizeof(body_), "{\"email\":\"%s\",\"password\":\"%s\",\"returnSecureToken\":true}",
             email, password);
    WiFiClientSecure client;
    Notifier::secure(client);
    HTTPClient http;
    http.setTimeout(10000);
    int code = -1;
    String reply;
    if (http.begin(client, "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key="
                           FIREBASE_API_KEY)) {
      http.addHeader("Content-Type", "application/json");
      collectBodyHeaders(http);
      code = http.POST(reinterpret_cast<uint8_t *>(body_), strlen(body_));
      if (code > 0 && !readBody(http, reply, 10000)) { client.stop(); code = -11; } // timeout
      else connectError(client, code);
      http.end();
    }
    netError_ = code <= 0;
    if (code == 200 && jsonString(jsonMember(reply.c_str(), "idToken"), token_, sizeof(token_))) {
      haveToken_ = true;
      notifier_->report("[CLOUD] Dang nhap OK (%lu ms).", (unsigned long)(millis() - t0));
      tokenAt_ = millis();
      return true;
    }
    haveToken_ = false;
    // 400 = wrong e-mail/password, unknown API key...: retrying soon will not help.
    const char *error = jsonMember(reply.c_str(), "error");
    if (code > 0 && (!error || !jsonString(jsonMember(error, "message"), message_, sizeof(message_))))
      snprintf(message_, sizeof(message_), "HTTP %d", code);
    notifier_->report("[CLOUD] Dang nhap Firebase loi: %.80s", message_);
    if (code == 400 || code == 403) state_ = State::AuthError;
    fail(code == 400 || code == 403 ? AUTH_RETRY_MS : 0);
    return false;
  }

  // No HTTP reply (code < 0): keep the TLS error and heap state for the log,
  // since -1 alone cannot tell DNS, TLS handshake and low memory apart.
  void connectError(WiFiClientSecure &client, int code) {
    char unused[2];
    int tls = client.lastError(unused, sizeof(unused));
    // -1: the TCP connection itself failed (no route to the Internet / timeout).
    snprintf(message_, sizeof(message_), "HTTP %d, TLS -0x%04X%s, heap %lu max %lu", code, unsigned(-tls),
             tls == -1 ? " (khong ket noi duoc Internet)" : "", (unsigned long)ESP.getFreeHeap(),
             (unsigned long)ESP.getMaxAllocHeap());
  }

  // ---- Realtime Database (REST) ----
  // method: GET, PUT or PATCH. Writes use print=silent (204, empty reply).
  bool request(const char *method, const char *path, const char *body) {
    const uint32_t t0 = millis();
    const bool fresh = !db_.connected(); // a new TLS handshake is needed
    gStageCloud.set(path);
    const bool write = body != nullptr;
    snprintf(url_, sizeof(url_), "%s/devices/%s/%s.json?%sauth=%s", base_, CLOUD_DEVICE_ID, path,
             write ? "print=silent&" : "", token_);
    // Every stop() (ours or HTTPClient's) wipes the TLS context, CA bundle
    // hook included, so attach it again before a possible reconnect.
    db_.setCACertBundle(caBundleStart, caBundleEnd - caBundleStart);
    if (!http_.begin(db_, url_)) return false;
    collectBodyHeaders(http_);
    int code = write ? http_.sendRequest(method, reinterpret_cast<uint8_t *>(const_cast<char *>(body)), strlen(body))
                     : http_.sendRequest(method);
    response_ = String();
    if (code == 200 && !readBody(http_, response_, 10000)) {
      db_.stop(); // Half-read reply: the kept-alive connection is unusable.
      code = -11;
    }
    if (code < 0) connectError(db_, code);
    http_.end();
    if (fresh && (code == 200 || code == 204)) {
      db_.setNoDelay(true); // Small requests: do not wait for Nagle.
      notifier_->report("[CLOUD] Ket noi CSDL moi + %s %s: %lu ms.", method, path, (unsigned long)(millis() - t0));
    }
    if (code == 200 || code == 204) return true;
    netError_ = code < 0;
    if (code == 401) haveToken_ = false; // Expired/revoked token: sign in again.
    if (code < 0) notifier_->report("[CLOUD] %s %s loi: %.80s", method, path, message_);
    else notifier_->report("[CLOUD] %s %s loi HTTP %d%s", method, path, code,
                           code == 401 ? " (kiem tra quyen trong /access)" : "");
    return false;
  }

  bool putInfo() {
    TextOut t(body_, sizeof(body_));
    char name[96];
    jsonEscape(name, sizeof(name), DEVICE_NAME);
    t.addf("{\"name\":\"%s\",\"telegramAvailable\":%s,\"gmailAvailable\":%s,\"maxItems\":%u,"
           "\"bootAt\":{\".sv\":\"timestamp\"}}",
           name, Notifier::telegramAvailable() ? "true" : "false",
           Notifier::gmailAvailable() ? "true" : "false", unsigned(NotifySettings::MAX_ITEMS));
    return t.ok && request("PUT", "info", body_);
  }

  static void settingsJson(TextOut &t, const NotifySettings &s) {
    // chatIds/emailTo are validated lists: no characters that need escaping.
    t.addf("\"telegramOn\":%s,\"gmailOn\":%s,\"chatIds\":\"%s\",\"emailTo\":\"%s\",\"inactiveMin\":%u",
           s.telegramOn ? "true" : "false", s.gmailOn ? "true" : "false", s.chatIds, s.emailTo,
           unsigned(s.inactiveMin));
  }

  bool putControlSettings(const NotifySettings &s) {
    TextOut t(body_, sizeof(body_));
    t.add("{");
    settingsJson(t, s);
    t.add("}");
    if (!t.ok || !request("PUT", "control/settings", body_)) return false;
    cloud_ = s;
    cloudKnown_ = true;
    return true;
  }

  // What the device actually uses, plus why a cloud request was refused.
  bool patchApplied(const char *error) {
    char escaped[sizeof(message_) * 2];
    jsonEscape(escaped, sizeof(escaped), error);
    TextOut t(body_, sizeof(body_));
    t.add("{");
    settingsJson(t, notifier_->settings());
    t.addf(",\"error\":\"%s\",\"at\":{\".sv\":\"timestamp\"}}", escaped);
    if (!t.ok || !request("PATCH", "applied", body_)) return false;
    appliedSent_ = true;
    return true;
  }

  // A change made on the device's own page wins over the cloud copy.
  bool uploadLocalSettings() {
    uint32_t rev = notifier_->localRevision();
    if (!putControlSettings(notifier_->settings())) return false;
    notifier_->markUploaded(rev);
    return patchApplied("");
  }

  bool pollControl() {
    if (!request("GET", "control", nullptr)) return false;
    // Read testAt now: every later request() replaces response_, which would
    // leave `control` pointing at freed memory (that made the first poll see
    // testAt = 0 and the second one replay an old test request).
    uint64_t testAt = 0;
    const char *control = response_.c_str();
    jsonUint64(jsonMember(control, "testAt"), testAt);
    const char *settings = jsonMember(control, "settings");
    if (!settings) {
      // Nothing in the cloud yet (first start): publish the device's settings.
      if (!putControlSettings(notifier_->settings())) return false;
    } else if (!applyCloudSettings(settings)) {
      return false;
    }
    if (!appliedSent_ && !patchApplied("")) return false;
    if (!controlSeen_) {
      lastTestAt_ = testAt; // A request older than this boot is not replayed.
      controlSeen_ = true;
    } else if (testAt > lastTestAt_) {
      lastTestAt_ = testAt;
      const char *reply = Notifier::testMessage(notifier_->requestTest(board_->read().batteryMv));
      char escaped[256];
      jsonEscape(escaped, sizeof(escaped), reply);
      snprintf(body_, sizeof(body_), "{\"testAt\":%llu,\"testMsg\":\"%s\"}", (unsigned long long)testAt, escaped);
      if (!request("PATCH", "applied", body_)) return false;
    }
    return true;
  }

  bool applyCloudSettings(const char *json) {
    NotifySettings raw;
    bool parsed = jsonBool(jsonMember(json, "telegramOn"), raw.telegramOn) &&
                  jsonBool(jsonMember(json, "gmailOn"), raw.gmailOn) &&
                  jsonString(jsonMember(json, "chatIds"), raw.chatIds, sizeof(raw.chatIds)) &&
                  jsonString(jsonMember(json, "emailTo"), raw.emailTo, sizeof(raw.emailTo));
    // Written by pages older than the inactivity setting: keep the device's value.
    uint64_t minutes = notifier_->inactiveMinutes();
    const char *inactive = jsonMember(json, "inactiveMin");
    parsed = parsed && (!inactive || jsonUint64(inactive, minutes));
    if (minutes > 100000) minutes = 100000; // buildSettings reports it as too large.
    raw.inactiveMin = uint16_t(minutes > 0xFFFF ? 0xFFFF : minutes);
    if (!parsed) { // The database rules make this unlikely; report it once.
      if (malformedReported_) return true;
      if (!patchApplied("Dữ liệu cài đặt trên cloud không đúng định dạng.")) return false;
      malformedReported_ = true;
      cloudKnown_ = false;
      return true;
    }
    malformedReported_ = false;
    if (cloudKnown_ && sameSettings(raw, cloud_)) return true; // Already handled.
    NotifySettings wanted;
    if (!buildSettings(wanted, raw.telegramOn, raw.gmailOn, raw.chatIds, raw.emailTo, uint32_t(minutes),
                       Notifier::telegramAvailable(), Notifier::gmailAvailable(), message_, sizeof(message_))) {
      if (!patchApplied(message_)) return false;
    } else {
      if (!sameSettings(wanted, notifier_->settings())) notifier_->saveSettings(wanted, false);
      if (!patchApplied("")) return false;
    }
    cloud_ = raw;
    cloudKnown_ = true;
    return true;
  }

  bool sendStatusIfDue(uint32_t now) {
    DeviceStatus s = board_->read();
    const uint32_t since = uint32_t(now - sentAt_);
    bool due = !sentOnce_ || since >= HEARTBEAT_MS || s.alarm != sent_.alarm || s.inactive != sent_.inactive ||
               (s.differsFrom(sent_) && since >= MIN_STATUS_MS);
    if (!due) return true;
    TextOut t(body_, sizeof(body_));
    t.add("{");
    formatStatusFields(t, s);
    t.add(",\"updatedAt\":{\".sv\":\"timestamp\"}}");
    if (!t.ok || !request("PUT", "status", body_)) return false;
    sent_ = s;
    sentAt_ = now;
    sentOnce_ = true;
    return true;
  }
};
