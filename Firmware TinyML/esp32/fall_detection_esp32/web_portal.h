#pragma once
// Local web page (http://<WEB_HOSTNAME>.local or the IP in the log): live
// activity/alarm/inactivity status, the alert settings (Telegram/Gmail
// on-off, chat IDs, recipient e-mails, inactivity limit) and the Wi-Fi
// networks. Plain HTTP over the device's own TCP/IP stack: reachable in the
// home network, or through the setup hotspot (notifier.h) where a captive
// DNS sends every name to the device so phones open the page by themselves. Runs in its own task on core 0 like the notifier,
// so a slow browser never delays sampling, the alarm or the loop watchdog.
// The same data is reachable from any network through cloud_sync.h.
#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <DNSServer.h>
#include "notifier.h"
#include "notify_settings.h"
#include "device_status.h"
#include "cloud_sync.h"
#include "web_page.h"
#include "wifi_page.h"
#include "wifi_config.h"

#ifndef WEB_HOSTNAME
#define WEB_HOSTNAME "baonga"
#endif
#define WEB_USER "admin"

class WebPortal {
 public:
  // Call after notifier.begin() succeeded (Wi-Fi configured).
  bool begin(Notifier &notifier, StatusBoard &board, const CloudSync &cloud) {
    notifier_ = &notifier;
    board_ = &board;
    cloud_ = &cloud;
    return xTaskCreatePinnedToCore(taskMain, "web", 8192, this, 1, nullptr, 0) == pdPASS;
  }

 private:
  WebServer server_{80};
  Notifier *notifier_ = nullptr;
  StatusBoard *board_ = nullptr;
  const CloudSync *cloud_ = nullptr;
  DNSServer dns_;
  bool dnsOn_ = false;
  char json_[1536], escaped_[600];

  static void taskMain(void *arg) { static_cast<WebPortal *>(arg)->run(); }

  void run() {
    // The listening socket needs the network stack: home Wi-Fi or the hotspot.
    while (WiFi.status() != WL_CONNECTED && !notifier_->apActive()) vTaskDelay(pdMS_TO_TICKS(500));
    if (MDNS.begin(WEB_HOSTNAME)) MDNS.addService("http", "tcp", 80);
    static const char *headers[] = {"X-Requested-With", "Host"};
    server_.collectHeaders(headers, 2);
    server_.on("/", HTTP_GET, [this] { if (allowed()) sendPage(); });
    server_.on("/api/status", HTTP_GET, [this] { if (allowed()) sendStatus(); });
    server_.on("/api/settings", HTTP_GET, [this] { if (allowed()) sendSettings(); });
    server_.on("/api/settings", HTTP_POST, [this] { if (allowed() && sameOrigin()) saveSettings(); });
    server_.on("/api/test", HTTP_POST, [this] { if (allowed() && sameOrigin()) sendTest(); });
    server_.on("/wifi", HTTP_GET, [this] { if (allowed()) sendWifiPage(); });
    server_.on("/api/wifi", HTTP_GET, [this] { if (allowed()) sendWifi(); });
    server_.on("/api/wifi", HTTP_POST, [this] { if (allowed() && sameOrigin()) saveWifi(); });
    server_.on("/api/wifi/scan", HTTP_GET, [this] { if (allowed()) sendScan(); });
    server_.onNotFound([this] { notFound(); });
    server_.begin();
    for (;;) {
      captiveDns();
      server_.handleClient();
      vTaskDelay(pdMS_TO_TICKS(5));
    }
  }

  // Hotspot only: answer every DNS name with the device, so the phone's
  // "sign in to network" check lands on the setup page.
  void captiveDns() {
    const bool ap = notifier_->apActive();
    if (ap && !dnsOn_) dnsOn_ = dns_.start(53, "*", WiFi.softAPIP());
    else if (!ap && dnsOn_) { dns_.stop(); dnsOn_ = false; }
    if (dnsOn_) dns_.processNextRequest();
  }

  // Phones probe e.g. connectivitycheck.gstatic.com/generate_204 when they
  // join the hotspot: send them to the page instead of "no Internet".
  void notFound() {
    if (dnsOn_) {
      const String host = server_.header("Host"), ip = WiFi.softAPIP().toString();
      if (host != ip) {
        server_.sendHeader("Location", "http://" + ip + "/wifi", true);
        server_.send(302, "text/plain", "");
        return;
      }
    }
    server_.send(404, "text/plain", "Not found");
  }

  // Optional HTTP Basic auth (WEB_PASSWORD in secrets.h).
  bool allowed() {
    if (!*WEB_PASSWORD || server_.authenticate(WEB_USER, WEB_PASSWORD)) return true;
    server_.requestAuthentication(BASIC_AUTH, "Thiet bi bao nga");
    return false;
  }
  // Writes need a header that a foreign web page cannot add without a CORS
  // preflight (which this server never approves): blocks cross-site requests.
  bool sameOrigin() {
    if (server_.header("X-Requested-With") == "fetch") return true;
    server_.send(403, "text/plain", "Forbidden");
    return false;
  }

  void sendJson(int code) {
    server_.sendHeader("Cache-Control", "no-store");
    server_.send(code, "application/json; charset=utf-8", json_);
  }
  void sendResult(int code, const char *message) {
    jsonEscape(escaped_, sizeof(escaped_), message);
    snprintf(json_, sizeof(json_), "{\"ok\":%s,\"msg\":\"%s\"}", code == 200 ? "true" : "false", escaped_);
    sendJson(code);
  }

  void sendPage() {
    server_.sendHeader("Cache-Control", "no-cache");
    server_.send_P(200, "text/html; charset=utf-8", WEB_PAGE, sizeof(WEB_PAGE) - 1);
  }

  void sendWifiPage() {
    server_.sendHeader("Cache-Control", "no-cache");
    server_.send_P(200, "text/html; charset=utf-8", WIFI_PAGE, sizeof(WIFI_PAGE) - 1);
  }

  void sendStatus() {
    static const char *const nets[] = {"off", "wait", "ok"};
    static const char *const clouds[] = {"off", "wait", "ok", "auth"};
    jsonEscape(escaped_, sizeof(escaped_), DEVICE_NAME);
    TextOut t(json_, sizeof(json_));
    t.addf("{\"device\":\"%s\",\"net\":\"%s\",\"cloud\":\"%s\",", escaped_,
           nets[static_cast<int>(notifier_->net())], clouds[static_cast<int>(cloud_->state())]);
    formatStatusFields(t, board_->read());
    t.add("}");
    sendJson(t.ok ? 200 : 500);
  }

  void sendSettings() {
    NotifySettings s = notifier_->settings();
    TextOut t(json_, sizeof(json_));
    // Validated lists contain nothing that needs JSON escaping.
    t.addf("{\"telegramOn\":%s,\"gmailOn\":%s,\"chatIds\":\"%s\",\"emailTo\":\"%s\","
           "\"telegramAvailable\":%s,\"gmailAvailable\":%s,\"maxItems\":%u,"
           "\"inactiveMin\":%u,\"maxInactiveMin\":%u}",
           s.telegramOn ? "true" : "false", s.gmailOn ? "true" : "false", s.chatIds, s.emailTo,
           Notifier::telegramAvailable() ? "true" : "false",
           Notifier::gmailAvailable() ? "true" : "false", unsigned(NotifySettings::MAX_ITEMS),
           unsigned(s.inactiveMin), unsigned(NotifySettings::INACTIVE_MAX_MIN));
    sendJson(t.ok ? 200 : 500);
  }

  void saveSettings() {
    NotifySettings s;
    char message[192];
    String chats = server_.arg("chatIds"), mails = server_.arg("emailTo");
    String inactive = server_.arg("inactiveMin");
    inactive.trim();
    uint32_t minutes = 0;
    if (chats.length() > 400 || mails.length() > 800) return sendResult(400, "Dữ liệu quá dài.");
    if (!parseMinutes(inactive.c_str(), minutes))
      return sendResult(400, "Cảnh báo bất động: nhập số phút (số nguyên), 0 để tắt.");
    if (!buildSettings(s, server_.arg("telegramOn") == "1", server_.arg("gmailOn") == "1", chats.c_str(),
                       mails.c_str(), minutes, Notifier::telegramAvailable(), Notifier::gmailAvailable(),
                       message, sizeof(message)))
      return sendResult(400, message);
    if (!notifier_->saveSettings(s, true))
      return sendResult(500, "Đã áp dụng nhưng không lưu được vào bộ nhớ; sẽ mất khi khởi động lại.");
    sendResult(200, CloudSync::configured() ? "Đã lưu cài đặt (sẽ đồng bộ lên cloud)." : "Đã lưu cài đặt.");
  }

  // ---- Wi-Fi networks. Passwords are never sent back to the browser. ----
  void sendWifi() {
    const WifiNetworks list = notifier_->wifiNetworks();
    char joined[WifiNetworks::SSID_CAP];
    notifier_->connectedSsid(joined, sizeof(joined));
    TextOut t(json_, sizeof(json_));
    // Validated SSIDs contain no quote/backslash/control characters.
    t.addf("{\"host\":\"" WEB_HOSTNAME "\",\"connected\":\"%s\",\"ip\":\"%s\",\"rssi\":%d,\"ap\":%s,\"apName\":\"%s\","
           "\"apIp\":\"%s\",\"apLocked\":%s,\"max\":%d,\"networks\":[",
           joined, *joined ? WiFi.localIP().toString().c_str() : "", *joined ? int(WiFi.RSSI()) : 0,
           notifier_->apActive() ? "true" : "false", notifier_->apName(), WiFi.softAPIP().toString().c_str(),
           notifier_->apHasPassword() ? "true" : "false", WifiNetworks::MAX);
    for (int i = 0; i < list.count; ++i)
      t.addf("%s{\"ssid\":\"%s\",\"open\":%s}", i ? "," : "", list.ssid[i], *list.pass[i] ? "false" : "true");
    static const char *const states[] = {"none", "connecting", "ok", "fail"};
    const Notifier::Attempt a = notifier_->attempt();
    t.addf("],\"attempt\":{\"ssid\":\"%s\",\"state\":\"%s\",\"reason\":%u}}", a.ssid, states[a.state],
           unsigned(a.reason));
    sendJson(t.ok ? 200 : 500);
  }

  // action=connect (ssid, pass: empty = saved password or open network),
  // action=forget (ssid).
  void saveWifi() {
    const String action = server_.arg("action"), ssid = server_.arg("ssid");
    String pass = server_.arg("pass");
    if (ssid.length() > 64 || pass.length() > 128) return sendResult(400, "Dữ liệu quá dài.");
    if (action == "forget") {
      if (!notifier_->forgetWifi(ssid.c_str())) return sendResult(404, "Không có mạng này trong danh sách đã lưu.");
      return sendResult(200, "Đã quên mạng.");
    }
    if (action != "connect") return sendResult(400, "Yêu cầu không hợp lệ.");
    if (!validSsid(ssid.c_str())) return sendResult(400, "Tên Wi-Fi phải dài 1-32 byte, không chứa dấu \" hoặc \\.");
    if (pass.length() == 0) {
      const WifiNetworks list = notifier_->wifiNetworks();
      const int at = list.find(ssid.c_str());
      if (at >= 0) pass = list.pass[at];
    }
    if (!validWifiPassword(pass.c_str()))
      return sendResult(400, "Mật khẩu Wi-Fi phải dài 8-63 ký tự.");
    notifier_->connectTo(ssid.c_str(), pass.c_str());
    sendResult(200, "Đang kết nối…");
  }

  // Scan without blocking: the first call starts it, the page asks again.
  void sendScan() {
    const int16_t n = WiFi.scanComplete();
    if (n == WIFI_SCAN_RUNNING) return sendRaw("{\"scanning\":true}");
    if (n < 0 || server_.arg("fresh") == "1") {
      WiFi.scanDelete();
      const bool started = WiFi.scanNetworks(true) == WIFI_SCAN_RUNNING;
      return sendRaw(started ? "{\"scanning\":true}" : "{\"scanning\":false,\"error\":true,\"list\":[]}");
    }
    TextOut t(json_, sizeof(json_));
    t.add("{\"scanning\":false,\"list\":[");
    int shown = 0;
    for (int i = 0; i < n && shown < 20; ++i) {
      const String name = WiFi.SSID(i);
      if (!validSsid(name.c_str())) continue; // Hidden or unprintable names.
      bool dup = false; // Strongest copy of each name only (results come sorted by signal).
      for (int j = 0; j < i && !dup; ++j) dup = WiFi.SSID(j) == name;
      if (dup) continue;
      t.addf("%s{\"ssid\":\"%s\",\"rssi\":%d,\"open\":%s}", shown++ ? "," : "", name.c_str(),
             int(WiFi.RSSI(i)), WiFi.encryptionType(i) == WIFI_AUTH_OPEN ? "true" : "false");
    }
    t.add("]}");
    sendJson(t.ok ? 200 : 500);
  }

  void sendRaw(const char *json) {
    snprintf(json_, sizeof(json_), "%s", json);
    sendJson(200);
  }

  void sendTest() {
    Notifier::TestResult r = notifier_->requestTest(board_->read().batteryMv);
    static const int codes[] = {200, 429, 409, 503};
    sendResult(codes[static_cast<int>(r)], Notifier::testMessage(r));
  }
};
