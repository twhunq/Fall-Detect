#pragma once
// Fall/SOS alerts over Wi-Fi: Telegram Bot API and Gmail SMTP (TLS 465).
// Runs in its own FreeRTOS task on core 0, so TLS handshakes and retries never
// delay sampling, the buzzer or the loop watchdog on core 1. TLS servers are
// verified with the CA bundle built into the ESP32 core.
// Which channels are on and who receives them is set from the web page
// (web_portal.h) and kept in NVS; secrets.h only supplies the first defaults.
// The same task runs Wi-Fi: it tries the saved networks in turn and, when none
// can be joined, opens a setup hotspot so the networks can be set on the page.
#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <stdarg.h>
#include <time.h>
#include "mbedtls/base64.h"
#include "notify_format.h"
#include "notify_settings.h"
#include "wifi_config.h"

#define MAIL_BOUNDARY "fall-alert-7f3a9c2e"

#if __has_include("secrets.h")
#include "secrets.h"
#endif
#ifndef WIFI_SSID
#define WIFI_SSID ""
#endif
#ifndef WIFI_PASSWORD
#define WIFI_PASSWORD ""
#endif
#ifndef TELEGRAM_BOT_TOKEN
#define TELEGRAM_BOT_TOKEN ""
#endif
#ifndef TELEGRAM_CHAT_IDS
#define TELEGRAM_CHAT_IDS ""
#endif
#ifndef GMAIL_ADDRESS
#define GMAIL_ADDRESS ""
#endif
#ifndef GMAIL_APP_PASSWORD
#define GMAIL_APP_PASSWORD ""
#endif
#ifndef ALERT_EMAIL_TO
#define ALERT_EMAIL_TO ""
#endif
#ifndef DEVICE_NAME
#define DEVICE_NAME "Thiet bi bao nga"
#endif
// 1: open the setup hotspot "BaoNga-Setup-XXXX" when no saved network can be
// joined (its password is WEB_PASSWORD if that has 8+ characters, else open).
// 0: no hotspot; without saved networks Wi-Fi then stays off.
#ifndef WIFI_SETUP_AP
#define WIFI_SETUP_AP 1
#endif
// ESP32-S3 Super Mini boards (small ceramic antenna) often fail to join at the
// default 19.5 dBm: AUTH_EXPIRE / ASSOC_EXPIRE / 4-way handshake timeouts and
// a link that passes no data, all seen on this board. 8.5 dBm is the usual fix
// (tried on the board: 8.5 joins at -67 dBm, 11 and 19.5 dBm keep failing).
#ifndef WIFI_TX_POWER
#define WIFI_TX_POWER WIFI_POWER_8_5dBm
#endif
#ifndef WEB_PASSWORD
#define WEB_PASSWORD ""
#endif

// Only one TLS session at a time. Each costs ~46 KB of RAM in this core
// (16 KB in + 16 KB out record buffers, peer certificate kept); free heap
// with Wi-Fi up is ~75 KB. Seen on the board: the cloud's kept-alive
// Firebase connection plus a Telegram/Gmail send drove the heap to 4 KB,
// Gmail failed, the cloud timed out and every reconnect failed in RSA
// certificate verification. Alerts have priority: the notifier raises
// alertWaiting and the cloud closes its connection and hands the gate over.
class TlsGate {
 public:
  volatile bool alertWaiting = false;
  bool begin() { mutex_ = xSemaphoreCreateMutex(); return mutex_ != nullptr; }
  bool take(uint32_t ms) { return mutex_ && xSemaphoreTake(mutex_, pdMS_TO_TICKS(ms)) == pdTRUE; }
  void give() { if (mutex_) xSemaphoreGive(mutex_); }
 private:
  SemaphoreHandle_t mutex_ = nullptr;
};

// Where each network task is right now, for the hang report in the main loop.
struct TaskStage {
  volatile const char *name = "init";
  volatile uint32_t since = 0;
  void set(const char *n) { name = n; since = millis(); }
};
inline TaskStage gStageNotify, gStageCloud;

extern const uint8_t caBundleStart[] asm("_binary_x509_crt_bundle_start");
extern const uint8_t caBundleEnd[] asm("_binary_x509_crt_bundle_end");

class Notifier {
 public:
  enum class Net : uint8_t { Off, Connecting, Online };

  // Credentials compiled in from secrets.h; without them a channel cannot be enabled.
  static bool telegramAvailable() { return *TELEGRAM_BOT_TOKEN; }
  static bool gmailAvailable() { return *GMAIL_ADDRESS && *GMAIL_APP_PASSWORD; }
  static bool telegramReady(const NotifySettings &s) { return telegramAvailable() && s.telegramOn && *s.chatIds; }
  static bool gmailReady(const NotifySettings &s) { return gmailAvailable() && s.gmailOn && *s.emailTo; }

  // Wi-Fi stays off only without saved networks and with WIFI_SETUP_AP 0.
  bool begin() {
    loadSettings();
    loadWifi();
    if (!wifi_.count && !WIFI_SETUP_AP) return false;
    events_ = xQueueCreate(8, sizeof(NotifyEvent));
    logs_ = xQueueCreate(8, sizeof(LogLine));
    if (!events_ || !logs_ || !tls_.begin()) return false;
    return xTaskCreatePinnedToCore(taskMain, "notify", 12288, this, 1, nullptr, 0) == pdPASS;
  }
  // Never blocks the caller; a full queue drops the event and says so.
  bool post(const NotifyEvent &e) {
    if (!events_) return false;
    if (xQueueSend(events_, &e, 0) == pdTRUE) return true;
    report("[NOTIFY] Hang doi day, bo tin nhan.");
    return false;
  }
  // Network-task messages are relayed through the loop's logger.
  bool nextLog(char *out, size_t cap) {
    LogLine line;
    if (!logs_ || xQueueReceive(logs_, &line, 0) != pdTRUE) return false;
    snprintf(out, cap, "%s", line.text);
    return true;
  }
  Net net() const { return net_; }
  TlsGate &tls() { return tls_; }

  // ---- Wi-Fi networks (web page) ----
  WifiNetworks wifiNetworks() const {
    portENTER_CRITICAL(&lock_);
    WifiNetworks copy = wifi_;
    portEXIT_CRITICAL(&lock_);
    return copy;
  }
  // Join `ssid` like a phone does: the current network is dropped, the new one
  // is tried for up to CONNECT_MS and saved only once it works; on failure the
  // saved networks are tried again. Caller validated ssid/password.
  void connectTo(const char *ssid, const char *password) {
    portENTER_CRITICAL(&lock_);
    snprintf(want_.ssid, sizeof(want_.ssid), "%s", ssid);
    snprintf(want_.pass, sizeof(want_.pass), "%s", password);
    snprintf(attempt_.ssid, sizeof(attempt_.ssid), "%s", ssid);
    attempt_.state = Attempt::Connecting;
    attempt_.reason = 0;
    connectRequest_ = true;
    portEXIT_CRITICAL(&lock_);
  }
  // Removes a saved network; leaves it at once if it is the one in use.
  bool forgetWifi(const char *ssid) {
    WifiNetworks list = wifiNetworks();
    if (!removeWifiNetwork(list, ssid)) return false;
    const bool ok = persistWifi(list);
    char joined[WifiNetworks::SSID_CAP];
    connectedSsid(joined, sizeof(joined));
    if (strcmp(joined, ssid) == 0) wifiRestart_ = true;
    report("[NET] Quen mang \"%s\", NVS=%s", ssid, ok ? "OK" : "LOI");
    return ok;
  }
  // Outcome of the last connectTo(), for the page. reason: Wi-Fi disconnect
  // reason code (15/202/204: password, 201: network not found), 0 = timeout.
  struct Attempt {
    enum State : uint8_t { None, Connecting, Ok, Fail } state = None;
    uint8_t reason = 0;
    char ssid[WifiNetworks::SSID_CAP] = "";
  };
  Attempt attempt() const {
    portENTER_CRITICAL(&lock_);
    Attempt copy = attempt_;
    portEXIT_CRITICAL(&lock_);
    return copy;
  }
  bool apActive() const { return apActive_; }
  const char *apName() const { return apName_; }
  bool apHasPassword() const { return strlen(WEB_PASSWORD) >= 8; }
  // SSID of the joined network (empty when not connected).
  void connectedSsid(char *out, size_t cap) const {
    portENTER_CRITICAL(&lock_);
    snprintf(out, cap, "%s", WiFi.status() == WL_CONNECTED ? joined_ : "");
    portEXIT_CRITICAL(&lock_);
  }
  // No battery reading = running from USB: Wi-Fi power save is pointless
  // there and slows every request (each packet waits for the next beacon).
  void setExternalPower(bool on) { externalPower_ = on; }

  NotifySettings settings() const {
    portENTER_CRITICAL(&lock_);
    NotifySettings copy = settings_;
    portEXIT_CRITICAL(&lock_);
    return copy;
  }
  // Read by the sensing loop every second; no copy of the whole settings.
  uint16_t inactiveMinutes() const { return inactiveMin_; }
  bool anyChannelReady() const {
    NotifySettings s = settings();
    return telegramReady(s) || gmailReady(s);
  }
  // Caller validates s (buildSettings). Applies at once; false if NVS failed.
  // A local change (device web page) is remembered, across reboots too, until
  // cloud_sync.h has copied it to the cloud, so the cloud cannot undo it.
  bool saveSettings(const NotifySettings &s, bool local) {
    portENTER_CRITICAL(&lock_);
    settings_ = s;
    inactiveMin_ = s.inactiveMin;
    if (local) { localRev_ = localRev_ + 1; uploadPending_ = true; }
    portEXIT_CRITICAL(&lock_);
    Preferences prefs;
    if (!prefs.begin("notify", false)) return false;
    bool ok = prefs.putUChar("ver", 1) == 1 && prefs.putBool("tg", s.telegramOn) == 1 &&
              prefs.putBool("gm", s.gmailOn) == 1 &&
              prefs.putString("chats", s.chatIds) == strlen(s.chatIds) &&
              prefs.putString("mails", s.emailTo) == strlen(s.emailTo) &&
              prefs.putUShort("inact", s.inactiveMin) == 2;
    if (local) ok = prefs.putBool("up", true) == 1 && ok;
    prefs.end();
    report("[NOTIFY] Cai dat moi (%s): Telegram=%s Gmail=%s bat dong=%u phut, NVS=%s",
           local ? "trang noi bo" : "cloud", s.telegramOn ? "ON" : "OFF", s.gmailOn ? "ON" : "OFF",
           unsigned(s.inactiveMin), ok ? "OK" : "LOI");
    return ok;
  }
  bool uploadPending() const { return uploadPending_; }
  uint32_t localRevision() const { return localRev_; }
  // The cloud now holds revision `rev`; a newer local save keeps it pending.
  void markUploaded(uint32_t rev) {
    portENTER_CRITICAL(&lock_);
    bool done = rev == localRev_;
    if (done) uploadPending_ = false;
    portEXIT_CRITICAL(&lock_);
    Preferences prefs;
    if (done && prefs.begin("notify", false)) { prefs.putBool("up", false); prefs.end(); }
  }

  // "Send a test message" from the local or the cloud page.
  enum class TestResult : uint8_t { Sent, TooSoon, ChannelsOff, QueueFull };
  TestResult requestTest(uint32_t batteryMv) {
    if (!anyChannelReady()) return TestResult::ChannelsOff;
    uint32_t now = millis();
    portENTER_CRITICAL(&lock_);
    bool soon = testedOnce_ && uint32_t(now - lastTestMs_) < TEST_INTERVAL_MS;
    if (!soon) { testedOnce_ = true; lastTestMs_ = now; }
    portEXIT_CRITICAL(&lock_);
    if (soon) return TestResult::TooSoon;
    NotifyEvent e;
    e.kind = NotifyEvent::Kind::Test;
    e.atMs = now;
    e.batteryMv = batteryMv;
    return post(e) ? TestResult::Sent : TestResult::QueueFull;
  }
  static const char *testMessage(TestResult r) {
    switch (r) {
      case TestResult::Sent: return "Đã gửi tin thử, kiểm tra Telegram/Gmail sau ít giây.";
      case TestResult::TooSoon: return "Vừa gửi thử, hãy đợi vài giây rồi thử lại.";
      case TestResult::ChannelsOff: return "Telegram và Gmail đều đang tắt.";
      default: return "Hàng đợi gửi đang đầy, thử lại sau.";
    }
  }

  // Log line relayed through the loop's logger (any task may call this).
  void report(const char *format, ...) {
    if (!logs_) return;
    LogLine line;
    va_list args;
    va_start(args, format);
    vsnprintf(line.text, sizeof(line.text), format, args);
    va_end(args);
    xQueueSend(logs_, &line, 0);
  }

  // TLS client verified with the core's CA bundle (shared with cloud_sync.h).
  static void secure(WiFiClientSecure &client) {
    client.setCACertBundle(caBundleStart, caBundleEnd - caBundleStart);
    client.setTimeout(IO_TIMEOUT_MS);
    client.setHandshakeTimeout(IO_TIMEOUT_MS / 1000);
  }

 private:
  struct LogLine { char text[120]; };
  QueueHandle_t events_ = nullptr, logs_ = nullptr;
  TlsGate tls_;
  volatile Net net_ = Net::Off;
  WifiNetworks wifi_;              // Shared: guarded by lock_.
  char joined_[WifiNetworks::SSID_CAP] = ""; // Guarded by lock_.
  char apName_[24] = "";
  volatile bool apActive_ = false, wifiRestart_ = false, connectRequest_ = false;
  struct Wanted { char ssid[WifiNetworks::SSID_CAP] = ""; char pass[WifiNetworks::PASS_CAP] = ""; };
  Wanted want_;          // Guarded by lock_ (set by the web task).
  Attempt attempt_;      // Guarded by lock_.
  Wanted pending_;       // Network task only: network being joined on request.
  bool pendingActive_ = false;
  uint32_t pendingSince_ = 0;
  volatile uint8_t lastReason_ = 0; // From the Wi-Fi event handler.
  static constexpr uint32_t CONNECT_MS = 20000;
  int tryIndex_ = -1;
  bool retryNow_ = true; // first attempt, or after a failed connect from the page
  uint32_t lastTry_ = 0, downSince_ = 0, apSince_ = 0, apUsedMs_ = 0;
  static constexpr uint32_t TRY_MS = 20000;        // per network attempt (weak networks need time)
  static constexpr uint32_t AP_AFTER_MS = 45000;   // offline this long -> setup hotspot
  static constexpr uint32_t AP_MAX_MS = 10UL * 60 * 1000; // per outage, saves battery
  static constexpr uint32_t AP_LINGER_MS = 30000;  // after joining, if nobody uses the hotspot
  volatile bool externalPower_ = false;
  bool powerSave_ = true;
  mutable portMUX_TYPE lock_ = portMUX_INITIALIZER_UNLOCKED;
  NotifySettings settings_; // Shared: guarded by lock_.
  NotifySettings active_;   // Network task's copy for the message being sent.
  volatile uint32_t localRev_ = 0;     // Guarded by lock_ for writes.
  volatile uint16_t inactiveMin_ = NotifySettings::INACTIVE_DEFAULT_MIN;
  volatile bool uploadPending_ = false;
  uint32_t lastTestMs_ = 0;
  bool testedOnce_ = false;
  static constexpr int ATTEMPTS = 5;
  static constexpr uint32_t RETRY_MS = 5000, WIFI_WAIT_MS = 20000, IO_TIMEOUT_MS = 10000;
  static constexpr uint32_t TEST_INTERVAL_MS = 15000;
  // The cloud notices alertWaiting within 250 ms, or after a request already
  // in flight (10 s timeout). Past this the alert is tried anyway.
  static constexpr uint32_t TLS_WAIT_MS = 15000;

  // Defaults come from secrets.h; anything stored from the web page wins.
  // Stored lists are re-validated so a corrupt NVS entry cannot reach SMTP.
  void loadSettings() {
    NotifySettings s;
    char bad[4];
    s.telegramOn = normalizeChatIds(TELEGRAM_CHAT_IDS, s.chatIds, bad, sizeof(bad)) == ListError::None &&
                   *s.chatIds;
    s.gmailOn = normalizeEmails(ALERT_EMAIL_TO, s.emailTo, bad, sizeof(bad)) == ListError::None && *s.emailTo;
    Preferences prefs;
    if (prefs.begin("notify", true)) {
      if (prefs.getUChar("ver", 0) == 1) {
        char raw[sizeof(s.emailTo)];
        s.telegramOn = prefs.getBool("tg", false);
        s.gmailOn = prefs.getBool("gm", false);
        raw[0] = '\0';
        prefs.getString("chats", raw, sizeof(raw));
        if (normalizeChatIds(raw, s.chatIds, bad, sizeof(bad)) != ListError::None) {
          s.chatIds[0] = '\0';
          s.telegramOn = false;
        }
        raw[0] = '\0';
        prefs.getString("mails", raw, sizeof(raw));
        if (normalizeEmails(raw, s.emailTo, bad, sizeof(bad)) != ListError::None) {
          s.emailTo[0] = '\0';
          s.gmailOn = false;
        }
        // Added later: older NVS records have no "inact" and keep the default.
        if (prefs.isKey("inact")) {
          uint16_t minutes = prefs.getUShort("inact", NotifySettings::INACTIVE_DEFAULT_MIN);
          s.inactiveMin = minutes <= NotifySettings::INACTIVE_MAX_MIN ? minutes
                                                                     : NotifySettings::INACTIVE_DEFAULT_MIN;
        }
        uploadPending_ = prefs.getBool("up", false);
      }
      prefs.end();
    }
    portENTER_CRITICAL(&lock_);
    settings_ = s;
    inactiveMin_ = s.inactiveMin;
    portEXIT_CRITICAL(&lock_);
  }

  // Saved list wins; the first start uses WIFI_SSID/WIFI_PASSWORD from secrets.h.
  void loadWifi() {
    WifiNetworks list;
    char message[8];
    Preferences prefs;
    bool stored = false;
    if (prefs.begin("wifi", true)) {
      if (prefs.isKey("n")) {
        stored = true;
        const int n = prefs.getUChar("n", 0);
        char key[4] = "s0", ssid[WifiNetworks::SSID_CAP], pass[WifiNetworks::PASS_CAP];
        // Added from the last to the first so the order is kept; each entry is
        // re-validated so a corrupt record cannot reach the Wi-Fi driver.
        for (int i = (n < WifiNetworks::MAX ? n : WifiNetworks::MAX) - 1; i >= 0; --i) {
          key[0] = 's'; key[1] = char('0' + i);
          ssid[0] = pass[0] = '\0';
          prefs.getString(key, ssid, sizeof(ssid));
          key[0] = 'p';
          if (prefs.isKey(key)) prefs.getString(key, pass, sizeof(pass));
          addWifiNetwork(list, ssid, pass, message, sizeof(message));
        }
      }
      prefs.end();
    }
    if (!stored && *WIFI_SSID) addWifiNetwork(list, WIFI_SSID, WIFI_PASSWORD, message, sizeof(message));
    portENTER_CRITICAL(&lock_);
    wifi_ = list;
    portEXIT_CRITICAL(&lock_);
  }

  bool persistWifi(const WifiNetworks &list) {
    portENTER_CRITICAL(&lock_);
    wifi_ = list;
    portEXIT_CRITICAL(&lock_);
    Preferences prefs;
    bool ok = prefs.begin("wifi", false);
    if (!ok) return false;
    ok = prefs.putUChar("n", uint8_t(list.count)) == 1;
    char key[4] = "s0";
    for (int i = 0; i < WifiNetworks::MAX; ++i) {
      key[0] = 's'; key[1] = char('0' + i);
      if (i < list.count) ok = prefs.putString(key, list.ssid[i]) == strlen(list.ssid[i]) && ok;
      else prefs.remove(key);
      key[0] = 'p';
      if (i < list.count) ok = prefs.putString(key, list.pass[i]) == strlen(list.pass[i]) && ok;
      else prefs.remove(key);
    }
    prefs.end();
    return ok;
  }

  void finishAttempt(Attempt::State state, uint8_t reason) {
    portENTER_CRITICAL(&lock_);
    attempt_.state = state;
    attempt_.reason = reason;
    portEXIT_CRITICAL(&lock_);
    pendingActive_ = false;
  }

  static void taskMain(void *arg) { static_cast<Notifier *>(arg)->run(); }

  void run() {
    WiFi.persistent(false);     // Credentials live in our own NVS record.
    WiFi.setAutoReconnect(false); // manageWifi() rotates through the saved networks.
    WiFi.mode(WIFI_STA);
    WiFi.setTxPower(WIFI_TX_POWER);
    WiFi.setSleep(true); // Modem sleep between beacons to save battery (see applyPowerSave).
    WiFi.onEvent([this](WiFiEvent_t, WiFiEventInfo_t info) { lastReason_ = info.wifi_sta_disconnected.reason; },
                 ARDUINO_EVENT_WIFI_STA_DISCONNECTED);
    uint8_t mac[6];
    WiFi.macAddress(mac);
    snprintf(apName_, sizeof(apName_), "BaoNga-Setup-%02X%02X", mac[4], mac[5]);
    net_ = Net::Connecting;
    downSince_ = millis();
    NotifySettings s = settings();
    report("[NET] Wi-Fi: %d mang da luu. Telegram=%s Gmail=%s", wifiNetworks().count,
           telegramReady(s) ? "ON" : "OFF", gmailReady(s) ? "ON" : "OFF");
    bool clockStarted = false;
    for (;;) {
      gStageNotify.set("manageWifi");
      manageWifi();
      if (net_ == Net::Online && !clockStarted) {
        configTzTime("ICT-7", "pool.ntp.org", "time.google.com");
        clockStarted = true;
      }
      applyPowerSave(false);
      NotifyEvent e;
      gStageNotify.set("idle");
      if (xQueueReceive(events_, &e, pdMS_TO_TICKS(1000)) == pdTRUE) {
        gStageNotify.set("deliver");
        applyPowerSave(true); // Alerts go out at full speed.
        deliver(e);
      }
    }
  }

  // Joined: keep it (the hotspot closes once nobody uses it). Not joined: try
  // the next saved network every TRY_MS; after AP_AFTER_MS offline, or with
  // no saved network, open the setup hotspot for at most AP_MAX_MS per outage.
  void manageWifi() {
    const uint32_t now = millis();
    if (connectRequest_) {
      portENTER_CRITICAL(&lock_);
      pending_ = want_;
      connectRequest_ = false;
      portEXIT_CRITICAL(&lock_);
      pendingActive_ = true;
      pendingSince_ = now;
      lastReason_ = 0;
      WiFi.disconnect(false, false);
      WiFi.begin(pending_.ssid, *pending_.pass ? pending_.pass : nullptr);
      report("[NET] Ket noi Wi-Fi \"%s\" theo yeu cau tu trang web...", pending_.ssid);
      return;
    }
    const bool up = WiFi.status() == WL_CONNECTED;
    if (pendingActive_) {
      const uint8_t reason = lastReason_;
      if (up && WiFi.SSID() == pending_.ssid) {
        WifiNetworks list = wifiNetworks();
        char message[8];
        addWifiNetwork(list, pending_.ssid, pending_.pass, message, sizeof(message));
        const bool saved = persistWifi(list);
        finishAttempt(Attempt::Ok, 0);
        tryIndex_ = 0;
        report("[NET] Da ket noi \"%s\", luu mang NVS=%s", pending_.ssid, saved ? "OK" : "LOI");
      } else if (reason == 15 || reason == 202 || reason == 204 || uint32_t(now - pendingSince_) >= CONNECT_MS) {
        // 15/204: 4-way handshake timeout, 202: auth failed = wrong password.
        finishAttempt(Attempt::Fail, reason == 15 || reason == 202 || reason == 204 ? reason : (reason == 201 ? 201 : 0));
        report("[NET] Khong ket noi duoc \"%s\" (ma %u); thu lai cac mang da luu.", pending_.ssid, unsigned(reason));
        WiFi.disconnect(false, false);
        retryNow_ = true; // Saved networks again, at once.
      } else {
        return; // Still joining.
      }
    }
    const WifiNetworks list = wifiNetworks();
    if (WiFi.status() == WL_CONNECTED && !wifiRestart_) {
      const String ssid = WiFi.SSID();
      if (net_ != Net::Online || ssid != joined_) {
        portENTER_CRITICAL(&lock_);
        snprintf(joined_, sizeof(joined_), "%s", ssid.c_str());
        portEXIT_CRITICAL(&lock_);
        report("[NET] Wi-Fi OK \"%s\", trang web: http://%s/", joined_, WiFi.localIP().toString().c_str());
      }
      net_ = Net::Online;
      downSince_ = now;
      apUsedMs_ = 0;
      if (apActive_ && uint32_t(now - apSince_) >= AP_LINGER_MS && WiFi.softAPgetStationNum() == 0) stopAp();
      return;
    }
    if (net_ == Net::Online) {
      report("[NET] Mat Wi-Fi, dang ket noi lai.");
      downSince_ = now;
    }
    net_ = Net::Connecting;
    const bool restart = wifiRestart_;
    wifiRestart_ = false;
    // Like a phone: scan, then join the strongest saved network that is on
    // the air, straight to its channel/BSSID. Absent ones are not tried.
    // A scan started from the page is left alone; it ends within seconds.
    if (list.count && WiFi.scanComplete() != WIFI_SCAN_RUNNING &&
        (restart || retryNow_ || uint32_t(now - lastTry_) >= TRY_MS)) {
      retryNow_ = false;
      if (tryIndex_ >= 0 && lastReason_)
        report("[NET] \"%s\" khong vao duoc (ma %u).", list.ssid[tryIndex_], unsigned(lastReason_));
      lastTry_ = now;
      lastReason_ = 0;
      WiFi.disconnect(false, false);
      const int16_t n = WiFi.scanNetworks(false, false, false, 120); // ~2 s, this task only
      int best = -1, bestAt = -1;
      int32_t bestRssi = -1000;
      for (int16_t i = 0; i < n; ++i) {
        const int at = list.find(WiFi.SSID(i).c_str());
        if (at >= 0 && WiFi.RSSI(i) > bestRssi) { best = i; bestAt = at; bestRssi = WiFi.RSSI(i); }
      }
      if (bestAt < 0) {
        tryIndex_ = -1;
        report("[NET] Khong thay mang Wi-Fi da luu nao (quet duoc %d mang).", int(n < 0 ? 0 : n));
      } else {
        tryIndex_ = bestAt;
        uint8_t bssid[6];
        memcpy(bssid, WiFi.BSSID(best), 6);
        const int32_t channel = WiFi.channel(best);
        WiFi.begin(list.ssid[bestAt], *list.pass[bestAt] ? list.pass[bestAt] : nullptr, channel, bssid);
        report("[NET] Ket noi \"%s\" (%ld dBm, kenh %ld)...", list.ssid[bestAt], long(bestRssi), long(channel));
      }
      WiFi.scanDelete();
    }
    if (!WIFI_SETUP_AP) return;
    const bool wanted = !list.count || uint32_t(now - downSince_) >= AP_AFTER_MS;
    if (!apActive_ && wanted && apUsedMs_ < AP_MAX_MS) startAp(now);
    if (apActive_ && list.count && uint32_t(now - apSince_) + apUsedMs_ >= AP_MAX_MS &&
        WiFi.softAPgetStationNum() == 0) {
      apUsedMs_ = AP_MAX_MS;
      stopAp();
      report("[NET] Tat diem phat cai dat de tiet kiem pin; tat/bat nguon de mo lai.");
    }
  }

  void startAp(uint32_t now) {
    applyPowerSave(true); // A soft AP cannot sleep.
    WiFi.mode(WIFI_AP_STA);
    const bool ok = WiFi.softAP(apName_, apHasPassword() ? WEB_PASSWORD : nullptr);
    WiFi.setTxPower(WIFI_TX_POWER); // A mode change resets it.
    apActive_ = ok;
    apSince_ = now;
    if (ok) report("[NET] Mo diem phat cai dat \"%s\"%s: vao http://%s/ de chon Wi-Fi.", apName_,
                   apHasPassword() ? " (mat khau = WEB_PASSWORD)" : " (khong mat khau)",
                   WiFi.softAPIP().toString().c_str());
    else report("[NET] Khong mo duoc diem phat cai dat.");
  }

  void stopAp() {
    apUsedMs_ += uint32_t(millis() - apSince_);
    WiFi.softAPdisconnect(true);
    WiFi.mode(WIFI_STA);
    WiFi.setTxPower(WIFI_TX_POWER);
    apActive_ = false;
    report("[NET] Dong diem phat cai dat.");
  }

  // Modem sleep only on battery and while no alert is being sent. Each packet
  // otherwise waits for the AP's next beacon: a TLS handshake (many round
  // trips) takes seconds and phone hotspots often time out.
  void applyPowerSave(bool sending) {
    const bool want = !sending && !externalPower_ && !apActive_;
    if (want == powerSave_) return;
    WiFi.setSleep(want);
    powerSave_ = want;
    if (!sending) report("[NET] Tiet kiem dien Wi-Fi: %s", want ? "BAT (chay pin)" : "TAT (cam USB, phan hoi nhanh)");
  }

  bool waitWifi() {
    for (uint32_t start = millis(); WiFi.status() != WL_CONNECTED; vTaskDelay(pdMS_TO_TICKS(200)))
      if (uint32_t(millis() - start) >= WIFI_WAIT_MS) return false;
    return true;
  }

  // Message buffers live here, not on the 12 KB task stack.
  char subject_[160], telegram_[1024], mailText_[640], mailHtml_[3584], escaped_[2048], body_[2176];

  void deliver(const NotifyEvent &e) {
    static const char *const names[] = {"NGA", "SOS", "TEST", "BAT DONG", "CU DONG LAI"};
    active_ = settings(); // A change made mid-delivery applies to the next alert.
    const bool tgOn = telegramReady(active_), mailOn = gmailReady(active_);
    if (!tgOn && !mailOn) {
      report("[NOTIFY] %s: Telegram va Gmail deu dang tat, khong gui.", names[static_cast<int>(e.kind)]);
      return;
    }
    report("[NOTIFY] Bat dau gui %s.", names[static_cast<int>(e.kind)]);
    char when[40] = "";
    time_t now = time(nullptr);
    if (now > 1700000000) { // NTP synchronised: back-date to the event time.
      time_t at = now - time_t(uint32_t(millis() - e.atMs) / 1000);
      struct tm local;
      localtime_r(&at, &local);
      strftime(when, sizeof(when), "%H:%M:%S · %d/%m/%Y", &local);
    }
    bool built = formatNotifySubject(subject_, sizeof(subject_), e.kind, DEVICE_NAME) &&
                 formatNotify(telegram_, sizeof(telegram_), NotifyStyle::Telegram, e, DEVICE_NAME, when) &&
                 formatNotify(mailText_, sizeof(mailText_), NotifyStyle::EmailText, e, DEVICE_NAME, when) &&
                 formatNotify(mailHtml_, sizeof(mailHtml_), NotifyStyle::EmailHtml, e, DEVICE_NAME, when);
    if (!built) report("[NOTIFY] Noi dung qua dai (DEVICE_NAME?), da cat bot.");
    bool tgDone = !tgOn, mailDone = !mailOn;
    uint8_t chatsSent = 0; // Bit i: chat i already has the message, a retry skips it.
    for (int attempt = 1; attempt <= ATTEMPTS && !(tgDone && mailDone); ++attempt) {
      if (attempt > 1) vTaskDelay(pdMS_TO_TICKS(RETRY_MS));
      if (!waitWifi()) { report("[NOTIFY] Chua co Wi-Fi (lan %d/%d).", attempt, ATTEMPTS); continue; }
      // Released between attempts, so the cloud can still show the alarm.
      tls_.alertWaiting = true;
      gStageNotify.set("tls-gate");
      const bool gate = tls_.take(TLS_WAIT_MS);
      if (!gate) report("[NOTIFY] Cho ket noi cloud dong qua lau, van gui.");
      gStageNotify.set("telegram");
      if (!tgDone) tgDone = sendTelegram(chatsSent);
      gStageNotify.set("gmail");
      if (!mailDone) mailDone = sendGmail();
      tls_.alertWaiting = false;
      if (gate) tls_.give();
    }
    report("[NOTIFY] %s: Telegram=%s Gmail=%s", names[static_cast<int>(e.kind)],
           !tgOn ? "-" : (tgDone ? "OK" : "LOI"), !mailOn ? "-" : (mailDone ? "OK" : "LOI"));
  }

  // Sends to every chat in the list (a group id works too) that is not yet
  // marked in `sent`; true once all of them have the message. One failing
  // chat does not stop the others, and a retry does not repeat delivered ones.
  bool sendTelegram(uint8_t &sent) {
    static_assert(NotifySettings::MAX_ITEMS <= 8, "sent is an 8-bit mask");
    if (!jsonEscape(escaped_, sizeof(escaped_), telegram_)) return false;
    bool ok = true;
    const char *cursor = active_.chatIds;
    char chat[32];
    for (unsigned i = 0; nextListItem(cursor, chat, sizeof(chat)); ++i) {
      if (sent & (1u << i)) continue;
      snprintf(body_, sizeof(body_),
               "{\"chat_id\":\"%s\",\"parse_mode\":\"HTML\",\"disable_web_page_preview\":true,\"text\":\"%s\"}",
               chat, escaped_);
      WiFiClientSecure client;
      secure(client);
      HTTPClient http;
      http.setTimeout(IO_TIMEOUT_MS);
      int code = -1;
      if (http.begin(client, "https://api.telegram.org/bot" TELEGRAM_BOT_TOKEN "/sendMessage")) {
        http.addHeader("Content-Type", "application/json");
        code = http.POST(reinterpret_cast<uint8_t *>(body_), strlen(body_));
        http.end();
      }
      if (code == 200) sent |= uint8_t(1u << i);
      else { report("[NOTIFY] Telegram chat %s loi, HTTP %d", chat, code); ok = false; }
    }
    return ok;
  }

  // ---- Minimal SMTP over implicit TLS (smtp.gmail.com:465, AUTH LOGIN) ----
  // Reads reply lines until the last one ("250 ..." not "250-..."). Polls
  // available()/read() itself with one overall deadline; -2: closed, -1: timed out.
  int smtpBytes_ = 0; // received in the last reply, for the failure report
  int smtpReply(WiFiClientSecure &c) {
    char line[160];
    size_t n = 0;
    smtpBytes_ = 0;
    for (uint32_t start = millis(); uint32_t(millis() - start) < IO_TIMEOUT_MS;) {
      const int avail = c.available();
      if (avail <= 0) {
        if (!c.connected()) return -2;
        vTaskDelay(pdMS_TO_TICKS(5));
        continue;
      }
      const int ch = c.read();
      if (ch < 0) continue;
      ++smtpBytes_;
      if (ch != '\n') {
        if (n < sizeof(line) - 1) line[n++] = char(ch);
        continue;
      }
      line[n] = '\0';
      const bool last = n >= 3 && (n == 3 || line[3] != '-');
      const int code = atoi(line);
      n = 0;
      if (last) return code;
    }
    return -1;
  }
  // Last SMTP reply code, for the failure report.
  int smtpLast_ = 0;
  bool smtpCommand(WiFiClientSecure &c, const char *command, int expect) {
    if (command) { c.print(command); c.print("\r\n"); }
    smtpLast_ = smtpReply(c);
    return smtpLast_ == expect;
  }
  static bool base64(const char *in, size_t len, char *out, size_t cap) {
    size_t written = 0;
    if (mbedtls_base64_encode(reinterpret_cast<unsigned char *>(out), cap, &written,
                              reinterpret_cast<const unsigned char *>(in), len) != 0) return false;
    out[written] = '\0';
    return true;
  }
  // RFC 2047 header value: UTF-8 split into short encoded words, folded lines.
  static bool printEncodedHeader(WiFiClientSecure &c, const char *name, const char *value) {
    char enc[80];
    c.print(name);
    c.print(": ");
    for (bool first = true; *value; first = false) {
      size_t n = utf8Prefix(value, 42);
      if (!n || !base64(value, n, enc, sizeof(enc))) return false;
      c.printf("%s=?UTF-8?B?%s?=", first ? "" : "\r\n ", enc);
      value += n;
    }
    c.print("\r\n");
    return true;
  }
  // Body part in 57-byte chunks -> 76-character base64 lines (RFC 2045).
  static bool printBase64Part(WiFiClientSecure &c, const char *type, const char *text) {
    char enc[80];
    c.printf("--" MAIL_BOUNDARY "\r\nContent-Type: %s; charset=UTF-8\r\n"
             "Content-Transfer-Encoding: base64\r\n\r\n", type);
    for (size_t at = 0, len = strlen(text); at < len; at += 57) {
      if (!base64(text + at, len - at < 57 ? len - at : 57, enc, sizeof(enc))) return false;
      c.print(enc);
      c.print("\r\n");
    }
    return true;
  }

  bool sendGmail() {
    WiFiClientSecure c;
    secure(c);
    if (!c.connect("smtp.gmail.com", 465)) { report("[NOTIFY] Gmail: khong ket noi/xac thuc TLS duoc."); return false; }
    char line[200], enc[160], password[40];
    size_t n = 0; // App Passwords are displayed as "abcd efgh ijkl mnop".
    for (const char *p = GMAIL_APP_PASSWORD; *p && n + 1 < sizeof(password); ++p)
      if (*p != ' ') password[n++] = *p;
    password[n] = '\0';
    const char *step = "chao (220)";
    bool ok = smtpCommand(c, nullptr, 220) && (step = "EHLO", smtpCommand(c, "EHLO esp32-fall-detector", 250)) &&
              (step = "AUTH LOGIN", smtpCommand(c, "AUTH LOGIN", 334)) &&
              base64(GMAIL_ADDRESS, strlen(GMAIL_ADDRESS), enc, sizeof(enc)) &&
              (step = "ten dang nhap", smtpCommand(c, enc, 334)) &&
              base64(password, strlen(password), enc, sizeof(enc));
    if (ok) step = "mat khau";
    if (ok && !smtpCommand(c, enc, 235)) {
      report("[NOTIFY] Gmail tu choi dang nhap: kiem tra GMAIL_ADDRESS va App Password.");
      ok = false;
    }
    if (ok) {
      step = "MAIL FROM";
      snprintf(line, sizeof(line), "MAIL FROM:<%s>", GMAIL_ADDRESS);
      ok = smtpCommand(c, line, 250);
    }
    if (ok) step = "RCPT TO";
    // A rejected address is skipped; the others still get the mail.
    const char *cursor = active_.emailTo;
    char to[96];
    unsigned accepted = 0;
    while (ok && nextListItem(cursor, to, sizeof(to))) {
      snprintf(line, sizeof(line), "RCPT TO:<%s>", to);
      c.print(line);
      c.print("\r\n");
      int reply = smtpReply(c);
      if (reply == 250 || reply == 251) ++accepted;
      else if (reply > 0) report("[NOTIFY] Gmail tu choi nguoi nhan %.60s (%d)", to, reply);
      else ok = false; // No reply: the session is lost.
    }
    if (ok && !accepted) step = "khong co nguoi nhan hop le";
    else if (ok) step = "DATA";
    ok = ok && accepted && smtpCommand(c, "DATA", 354);
    if (ok) {
      step = "noi dung thu";
      ok = base64(DEVICE_NAME, strlen(DEVICE_NAME), enc, sizeof(enc));
      c.printf("From: =?UTF-8?B?%s?= <%s>\r\nTo: %s\r\n", enc, GMAIL_ADDRESS, active_.emailTo);
      ok = ok && printEncodedHeader(c, "Subject", subject_);
      // High priority so phones surface the alert prominently.
      c.print("X-Priority: 1\r\nImportance: high\r\nMIME-Version: 1.0\r\n"
              "Content-Type: multipart/alternative; boundary=\"" MAIL_BOUNDARY "\"\r\n\r\n");
      ok = ok && printBase64Part(c, "text/plain", mailText_) && printBase64Part(c, "text/html", mailHtml_);
      c.print("--" MAIL_BOUNDARY "--\r\n");
      ok = ok && smtpCommand(c, ".", 250);
    }
    if (!ok) {
      char unused[2];
      report("[NOTIFY] Gmail: that bai o buoc %s (ma %d, %d byte), TLS -0x%04X, ket noi %s.", step, smtpLast_,
             smtpBytes_, unsigned(-c.lastError(unused, sizeof(unused))), c.connected() ? "con" : "da dong");
    }
    c.print("QUIT\r\n");
    c.stop();
    return ok;
  }
};
