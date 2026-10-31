/* ==========================================================================
 * telegram_alert.h
 * --------------------------------------------------------------------------
 * Gui canh bao NGA ve Telegram cua nguoi than (duong du phong khi relay
 * khong dung duoc, xem src/main.cpp).
 *
 * NGUYEN TAC: KHONG dung thu vien Telegram nao (khong UniversalTelegramBot,
 * khong ArduinoJson). Tu mo ket noi TLS bang WiFiClientSecure roi soan tay
 * mot HTTP request POST gui toi Bot API.
 *
 * Tin nhan dung parse_mode = HTML. Moi noi dung dong (ten WiFi...) deu duoc
 * escape truoc khi chen vao - mot ten WiFi co ky tu '<' se lam hong ca tin.
 *
 * --------------------------------------------------------------------------
 * CAN LAM TRUOC KHI NAP (1 lan duy nhat). Dien ket qua vao device_secrets.h
 * (TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID) hoac cau hinh tu app qua BLE:
 *
 *  Buoc 1 - Tao bot va lay TOKEN:
 *      - Mo Telegram, tim tai khoan  @BotFather
 *      - Go lenh  /newbot  roi dat ten cho bot theo huong dan
 *      - BotFather tra ve mot chuoi dang:
 *            8123456789:AAG7x-abcdefGHIJKLmnopQRSTuvwx1234567
 *
 *  Buoc 2 - Lay CHAT ID (noi nhan canh bao):
 *      - Tim bot vua tao, bam Start va gui cho no 1 tin bat ky. Buoc nay BAT
 *        BUOC - Telegram khong cho bot nhan tin truoc cho nguoi chua tung
 *        nhan tin voi no.
 *      - Mo trinh duyet, dan dia chi sau (thay <TOKEN> bang token o Buoc 1):
 *            https://api.telegram.org/bot<TOKEN>/getUpdates
 *      - Tim so trong phan  "chat":{"id":123456789,...}
 *
 *  Muon canh bao ve mot NHOM: tao nhom, moi bot vao nhom, gui 1 tin trong
 *  nhom roi lam lai getUpdates - chat id cua nhom la so AM, VD:
 *  -1001234567890 (dien nguyen ca dau tru).
 *
 * --------------------------------------------------------------------------
 * LUU Y KHI SUA FILE NAY: file luu bang UTF-8 (co dau tieng Viet va bieu
 * tuong trong noi dung tin nhan). Dung mo/luu lai bang trinh soan thao cu
 * dat mac dinh ANSI/Windows-1258.
 * ========================================================================== */

#ifndef TELEGRAM_ALERT_H
#define TELEGRAM_ALERT_H

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <time.h>

#include "device_config.h"
// WIFI_SSID, WIFI_PASSWORD, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID: gia tri mac
// dinh khi app chua cau hinh. Khong hardcode o day de khong lo bi mat.
#if __has_include("device_secrets.h")
#include "device_secrets.h"
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
#ifndef TELEGRAM_CHAT_ID
#define TELEGRAM_CHAT_ID ""
#endif

// ==========================================================================
// CAU HINH
// ==========================================================================
// Gui 1 tin "he thong da khoi dong" ngay sau khi vao duoc WiFi - de kiem tra
// token/chat id ma khong can gia vo nga. Dat 0 neu khong muon nhan tin nay.
#define TELEGRAM_SEND_BOOT_MESSAGE 1

// ---- Ten hien thi trong tin nhan ----
// VD "Bà Nguyễn Thị A - phòng ngủ tầng 2". Sketch co the dat ten rieng
// truoc khi include file nay.
#ifndef TELEGRAM_DEVICE_NAME
#define TELEGRAM_DEVICE_NAME "Thiết bị giám sát #1"
#endif

// ---- Mui gio de hien thi thoi gian that ----
// Viet Nam la GMT+7, khong co gio mua he.
#define TZ_OFFSET_SEC   (7 * 3600)
#define TZ_DST_SEC      0

// ==========================================================================
// Cac nguong thoi gian
// ==========================================================================
#define WIFI_CONNECT_TIMEOUT_MS   15000UL  // toi da 15s cho lan ket noi dau
#define WIFI_RECONNECT_TIMEOUT_MS 8000UL   // toi da 8s cho cac lan ket noi lai
#define TELEGRAM_HTTP_TIMEOUT_MS  10000UL  // toi da 10s cho 1 request HTTPS
#define TELEGRAM_MIN_INTERVAL_MS  60000UL  // toi thieu 60s giua 2 tin canh bao
#define NTP_SYNC_TIMEOUT_MS       4000UL   // toi da 4s cho lan dong bo gio dau

#define TELEGRAM_API_HOST "api.telegram.org"
#define TELEGRAM_API_PORT 443

// Duong ke ngang trang tri trong tin nhan.
#define TG_RULE "━━━━━━━━━━━━━━━━━━"

class TelegramAlert {
public:
  TelegramAlert()
      : _cfg(nullptr), _lastSentTime(0), _hasSentOnce(false),
        _timeSynced(false) {}

  // ------------------------------------------------------------------------
  // Gan nguon cau hinh chay duoc sua tu app (xem device_config.h).
  //
  // Khong gan thi lop nay dung cac #define trong device_secrets.h.
  //
  // Phai goi TRUOC begin(), vi begin() la cho ket noi WiFi.
  // ------------------------------------------------------------------------
  void setConfig(DeviceConfig *cfg) { _cfg = cfg; }

  // ------------------------------------------------------------------------
  // Ket noi WiFi. Tra ve true neu vao mang thanh cong.
  //
  // QUAN TRONG: ham nay KHONG bao gio treo vinh vien. Neu khong co WiFi,
  // no bao loi roi tra ve false - canh bao qua BLE khong duoc phep phu thuoc
  // vao viec co mang.
  // ------------------------------------------------------------------------
  bool begin() {
    Serial.print(F("[WIFI] Dang ket noi toi mang '"));
    Serial.print(_ssid());
    Serial.println(F("'..."));

    WiFi.mode(WIFI_STA);
    WiFi.begin(_ssid(), _matKhau());

    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED &&
           millis() - start < WIFI_CONNECT_TIMEOUT_MS) {
      delay(250);
      Serial.print(F("."));
    }
    Serial.println();

    if (WiFi.status() != WL_CONNECTED) {
      Serial.println(F("[WIFI] [LOI] Khong ket noi duoc WiFi sau 15 giay."));
      Serial.println(F("[WIFI]       He thong VAN CHAY - van canh bao qua BLE,"));
      Serial.println(F("[WIFI]       chi khong gui duoc Telegram."));
      Serial.println(F("[WIFI]       Kiem tra lai ten mang / mat khau, va nho"));
      Serial.println(F("[WIFI]       rang ESP32 CHI bat duoc WiFi 2.4GHz."));
      return false;
    }

    Serial.print(F("[WIFI] [OK] Da ket noi. Dia chi IP: "));
    Serial.println(WiFi.localIP());
    Serial.print(F("[WIFI] Cuong do song (RSSI): "));
    Serial.print(WiFi.RSSI());
    Serial.println(F(" dBm"));

    syncTime();

    if (!isConfigured()) {
      Serial.println(F("[TELEGRAM] [CANH BAO] Chua dien TOKEN/CHAT_ID trong"));
      Serial.println(F("[TELEGRAM]            device_secrets.h - se KHONG gui"));
      Serial.println(F("[TELEGRAM]            duoc tin nhan nao. Xem huong dan"));
      Serial.println(F("[TELEGRAM]            2 buoc o dau telegram_alert.h."));
      return true;
    }

#if TELEGRAM_SEND_BOOT_MESSAGE
    sendBootMessage();
#endif

    return true;
  }

  bool isConnected() const { return WiFi.status() == WL_CONNECTED; }

  // Kiem tra da co TOKEN/CHAT_ID that chua - tu app hoac tu device_secrets.h.
  bool isConfigured() const {
    const char *tok = _token();
    const char *chat = _chatId();
    return strcmp(tok, "DIEN_TOKEN_BOT_VAO_DAY") != 0 &&
           strcmp(chat, "DIEN_CHAT_ID_VAO_DAY") != 0 && strlen(tok) > 0 &&
           strlen(chat) > 0;
  }

  // ------------------------------------------------------------------------
  // Gui canh bao NGA. Tu dong chong gui trung lap (toi thieu 60 giay giua
  // 2 lan) de neu nguoi bi nga nam yen mot cho, may khong spam lien tuc.
  // ------------------------------------------------------------------------
  bool sendFallAlert(float confidence) {
    if (!isConfigured()) {
      return false;
    }

    unsigned long now = millis();
    if (_hasSentOnce && (now - _lastSentTime) < TELEGRAM_MIN_INTERVAL_MS) {
      Serial.println(F("[TELEGRAM] Bo qua: vua gui canh bao cach day chua 60 giay."));
      return false;
    }

    if (!ensureWiFi()) {
      Serial.println(F("[TELEGRAM] [LOI] Mat WiFi, khong gui duoc canh bao."));
      return false;
    }

    bool ok = sendMessage(buildAlertMessage(confidence, now));
    if (ok) {
      _lastSentTime = now;
      _hasSentOnce = true;
      Serial.println(F("[TELEGRAM] [OK] Da gui canh bao nga ve Telegram."));
    } else {
      Serial.println(F("[TELEGRAM] [LOI] Gui canh bao that bai."));
    }
    return ok;
  }

private:
  // ------------------------------------------------------------------------
  // Bon truong cau hinh: uu tien ban nguoi dung nhap tu app (luu trong NVS),
  // khong co thi dung #define trong device_secrets.h.
  // ------------------------------------------------------------------------
  const char *_ssid() const {
    return (_cfg != nullptr && _cfg->daCauHinhWiFi()) ? _cfg->ssid().c_str()
                                                      : WIFI_SSID;
  }

  const char *_matKhau() const {
    return (_cfg != nullptr && _cfg->daCauHinhWiFi()) ? _cfg->matKhau().c_str()
                                                      : WIFI_PASSWORD;
  }

  const char *_token() const {
    return (_cfg != nullptr && _cfg->daCauHinhTelegram())
               ? _cfg->token().c_str()
               : TELEGRAM_BOT_TOKEN;
  }

  const char *_chatId() const {
    return (_cfg != nullptr && _cfg->daCauHinhTelegram())
               ? _cfg->chatId().c_str()
               : TELEGRAM_CHAT_ID;
  }

  DeviceConfig *_cfg;
  unsigned long _lastSentTime;
  bool _hasSentOnce;
  bool _timeSynced;

  // ========================================================================
  // DONG BO GIO THAT
  // ------------------------------------------------------------------------
  // Lay gio that qua NTP (co san trong ESP32 core) de tin nhan ghi dang
  // 21:34:05 16/08/2026 thay vi "sau 12 phut ke tu khi khoi dong".
  // ========================================================================
  void syncTime() {
    configTime(TZ_OFFSET_SEC, TZ_DST_SEC, "pool.ntp.org", "time.google.com",
               "time.cloudflare.com");

    struct tm ti;
    if (getLocalTime(&ti, NTP_SYNC_TIMEOUT_MS)) {
      _timeSynced = true;
      char buf[40];
      strftime(buf, sizeof(buf), "%H:%M:%S %d/%m/%Y", &ti);
      Serial.print(F("[TIME] [OK] Da dong bo gio: "));
      Serial.println(buf);
    } else {
      Serial.println(F("[TIME] [CANH BAO] Chua dong bo duoc gio qua NTP."));
      Serial.println(F("[TIME]            Tin nhan se ghi thoi gian chay may"));
      Serial.println(F("[TIME]            thay vi gio that."));
    }
  }

  // Tra ve chuoi gio that, VD "21:34:05 · 16/08/2026". Chuoi rong neu chua
  // dong bo duoc gio.
  String clockString() {
    struct tm ti;
    // Chua tung dong bo duoc thi cho lau hon mot chut (co the mang vua len
    // lai); da dong bo roi thi doc gan nhu tuc thi.
    if (!getLocalTime(&ti, _timeSynced ? 100 : 1500)) {
      return String();
    }
    _timeSynced = true;
    char buf[48];
    strftime(buf, sizeof(buf), "%H:%M:%S \xC2\xB7 %d/%m/%Y", &ti);
    return String(buf);
  }

  // ========================================================================
  // SOAN NOI DUNG TIN NHAN
  // ========================================================================

  // ---- Tin canh bao nga ----
  String buildAlertMessage(float confidence, unsigned long now) {
    String m;
    m.reserve(512);

    m += F("🚨 <b>CẢNH BÁO NGÃ</b> 🚨\n");
    m += F("<i>Hệ thống AIoT giám sát người cao tuổi</i>\n");
    m += F(TG_RULE "\n");

    // Ten bien khong dat la "clock": <time.h> da co san ham clock().
    String nowStr = clockString();
    if (nowStr.length() > 0) {
      m += F("🕒 <b>Thời điểm:</b> ");
      m += nowStr;
      m += F("\n");
    } else {
      m += F("🕒 <b>Thời điểm:</b> sau ");
      m += formatUptime(now);
      m += F(" kể từ khi thiết bị khởi động\n");
    }

    m += F("🎯 <b>Độ tin cậy:</b> ");
    m += String(confidence * 100.0f, 1);
    m += F("%  ");
    m += confidenceBar(confidence);
    m += F("\n");

    m += F("🏷 <b>Thiết bị:</b> ");
    m += htmlEscape(F(TELEGRAM_DEVICE_NAME));
    m += F("\n");

    m += F("📶 <b>Sóng WiFi:</b> ");
    m += String(WiFi.RSSI());
    m += F(" dBm\n");

    m += F(TG_RULE "\n");
    m += F("‼️ <b>VUI LÒNG KIỂM TRA NGƯỜI THÂN NGAY</b>");
    return m;
  }

  // ---- Tin khoi dong ----
  void sendBootMessage() {
    String m;
    m.reserve(512);

    m += F("✅ <b>HỆ THỐNG ĐÃ SẴN SÀNG</b>\n");
    m += F("<i>AIoT cảnh báo ngã cho người cao tuổi · Camera K230</i>\n");
    m += F(TG_RULE "\n");

    m += F("🏷 <b>Thiết bị:</b> ");
    m += htmlEscape(F(TELEGRAM_DEVICE_NAME));
    m += F("\n");

    m += F("📶 <b>WiFi:</b> ");
    m += htmlEscape(String(_ssid()));
    m += F(" (");
    m += String(WiFi.RSSI());
    m += F(" dBm)\n");

    m += F("🌐 <b>Địa chỉ IP:</b> <code>");
    m += WiFi.localIP().toString();
    m += F("</code>\n");

    String nowStr = clockString();
    if (nowStr.length() > 0) {
      m += F("🕒 <b>Thời gian:</b> ");
      m += nowStr;
      m += F("\n");
    }

    m += F(TG_RULE "\n");
    m += F("🟢 Đang giám sát. Bạn sẽ nhận được cảnh báo ngay khi phát hiện ngã.");

    if (sendMessage(m)) {
      Serial.println(F("[TELEGRAM] [OK] Da gui tin nhan kiem tra khi khoi dong."));
    }
  }

  // ------------------------------------------------------------------------
  // Gui mot tin nhan chu (dinh dang HTML).
  // ------------------------------------------------------------------------
  bool sendMessage(const String &html) {
    String form;
    form.reserve(html.length() * 3 + 256);

    form += F("chat_id=");
    form += urlEncode(String(_chatId()));
    form += F("&parse_mode=HTML");
    // Tat khung xem truoc lien ket cho tin nhan gon gang.
    form += F("&disable_web_page_preview=true");
    form += F("&text=");
    form += urlEncode(html);

    return httpPost(F("sendMessage"), form);
  }

  // ------------------------------------------------------------------------
  // Neu mat WiFi thi thu ket noi lai (co gioi han thoi gian).
  // ------------------------------------------------------------------------
  bool ensureWiFi() {
    if (WiFi.status() == WL_CONNECTED) {
      return true;
    }

    Serial.println(F("[WIFI] Mat ket noi, dang thu ket noi lai..."));
    WiFi.disconnect();
    WiFi.begin(_ssid(), _matKhau());

    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED &&
           millis() - start < WIFI_RECONNECT_TIMEOUT_MS) {
      delay(200);
    }
    return WiFi.status() == WL_CONNECTED;
  }

  // ------------------------------------------------------------------------
  // Soan tay mot HTTP request POST gui qua ket noi TLS toi Bot API Telegram.
  //
  // Dung POST chu khong phai GET: tin nhan tieng Viet co dau sau khi ma hoa
  // percent-encoding dai gap 3 lan, nhet het vao duong dan URL cua GET la
  // vuot gioi han va tin nhan se bi tu choi.
  // ------------------------------------------------------------------------
  bool httpPost(const __FlashStringHelper *method, const String &form) {
    WiFiClientSecure client;

    // Bo qua viec kiem tra chung chi CA cua may chu Telegram.
    // Danh doi: don gian va khong can nhung chung chi goc vao firmware
    // (chung chi con co han su dung, het han la he thong chet lang).
    // Du lieu gui di chi la mot dong canh bao, khong co thong tin nhay cam,
    // nen muc rui ro nay chap nhan duoc voi de tai nay.
    client.setInsecure();
    client.setTimeout(TELEGRAM_HTTP_TIMEOUT_MS / 1000);

    if (!client.connect(TELEGRAM_API_HOST, TELEGRAM_API_PORT)) {
      Serial.println(F("[TELEGRAM] [LOI] Khong mo duoc ket noi TLS toi api.telegram.org"));
      return false;
    }

    client.print(F("POST /bot"));
    client.print(_token());
    client.print(F("/"));
    client.print(method);
    client.print(F(" HTTP/1.1\r\nHost: "));
    client.print(F(TELEGRAM_API_HOST));
    client.print(F("\r\nUser-Agent: ESP32-AIoT-FallDetect\r\n"
                   "Content-Type: application/x-www-form-urlencoded\r\n"
                   "Connection: close\r\nContent-Length: "));
    client.print(form.length());
    client.print(F("\r\n\r\n"));
    client.print(form);

    // ---- Doc dong trang thai HTTP dau tien, VD: "HTTP/1.1 200 OK" ----
    String statusLine;
    unsigned long start = millis();
    while (millis() - start < TELEGRAM_HTTP_TIMEOUT_MS) {
      if (client.available()) {
        char c = client.read();
        if (c == '\n') {
          break;
        }
        if (c != '\r') {
          statusLine += c;
        }
        if (statusLine.length() > 80) {
          break; // du lieu la, dung doc
        }
      } else if (!client.connected()) {
        break;
      } else {
        delay(5);
      }
    }

    // Doc them phan than de lay mo ta loi cua Telegram (rat huu ich khi go
    // roi: no noi ro sai o dau, VD "can't parse entities").
    String body;
    if (statusLine.indexOf(F("200")) < 0) {
      unsigned long t = millis();
      while (millis() - t < 1500UL && body.length() < 400) {
        if (client.available()) {
          body += (char)client.read();
        } else if (!client.connected()) {
          break;
        } else {
          delay(5);
        }
      }
    }
    client.stop();

    if (statusLine.length() == 0) {
      Serial.println(F("[TELEGRAM] [LOI] Het thoi gian cho, may chu khong tra loi."));
      return false;
    }

    bool ok = (statusLine.indexOf(F("200")) >= 0);
    if (!ok) {
      Serial.print(F("[TELEGRAM] [LOI] May chu tra ve: "));
      Serial.println(statusLine);
      if (body.length() > 0) {
        Serial.print(F("[TELEGRAM]       Chi tiet: "));
        Serial.println(body);
      }
      Serial.println(F("[TELEGRAM]       Loi 401 = sai TOKEN."));
      Serial.println(F("[TELEGRAM]       Loi 400 = sai CHAT_ID, hoac ban chua"));
      Serial.println(F("[TELEGRAM]                 bam Start / nhan tin cho bot."));
    }
    return ok;
  }

  // ------------------------------------------------------------------------
  // Escape 3 ky tu ma Telegram hieu la the HTML. Bat buoc phai lam voi moi
  // noi dung dong (ten WiFi, thong bao loi...): mot cai ten WiFi kieu
  // "Nha <A>" ma khong escape se lam Telegram tu choi ca tin nhan voi loi
  // "can't parse entities".
  // ------------------------------------------------------------------------
  static String htmlEscape(const String &src) {
    String out;
    out.reserve(src.length() + 16);
    for (size_t i = 0; i < src.length(); i++) {
      char c = src.charAt(i);
      if (c == '&') {
        out += F("&amp;");
      } else if (c == '<') {
        out += F("&lt;");
      } else if (c == '>') {
        out += F("&gt;");
      } else {
        out += c;
      }
    }
    return out;
  }

  static String htmlEscape(const __FlashStringHelper *src) {
    return htmlEscape(String(src));
  }

  // ------------------------------------------------------------------------
  // Ma hoa chuoi theo chuan percent-encoding de nhet an toan vao than
  // request. Cac ky tu nhu dau cach, xuong dong, dau '&' deu phai doi thanh
  // %XX, neu khong request HTTP se bi hong.
  //
  // Chu tieng Viet co dau va bieu tuong deu la UTF-8 nhieu byte - vong lap
  // nay ma hoa TUNG BYTE nen chung di qua an toan.
  // ------------------------------------------------------------------------
  static String urlEncode(const String &src) {
    // Khong dat ten bien la "HEX": Arduino.h da dinh nghia san macro
    // #define HEX 16 (dung cho Serial.print(x, HEX)), se gay loi bien dich.
    static const char *HEX_DIGITS = "0123456789ABCDEF";
    String out;
    out.reserve(src.length() * 3);

    for (size_t i = 0; i < src.length(); i++) {
      char c = src.charAt(i);
      if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') ||
          (c >= 'a' && c <= 'z') || c == '-' || c == '_' || c == '.' ||
          c == '~') {
        out += c;
      } else {
        out += '%';
        out += HEX_DIGITS[((unsigned char)c >> 4) & 0x0F];
        out += HEX_DIGITS[(unsigned char)c & 0x0F];
      }
    }
    return out;
  }

  // ------------------------------------------------------------------------
  // Thanh do tin cay bang ky tu khoi, VD 92% -> "▰▰▰▰▰▰▰▰▰▱".
  // Nhin la biet ngay muc do chac chan ma khong phai doc con so.
  // ------------------------------------------------------------------------
  static String confidenceBar(float confidence) {
    int filled = (int)(confidence * 10.0f + 0.5f);
    if (filled < 0) filled = 0;
    if (filled > 10) filled = 10;

    String s;
    for (int i = 0; i < 10; i++) {
      s += (i < filled) ? F("▰") : F("▱");
    }
    return s;
  }

  // ------------------------------------------------------------------------
  // Doi millis() thanh chuoi de doc, VD: "2 phut 05 giay". Chi dung khi
  // chua dong bo duoc gio that qua NTP.
  // ------------------------------------------------------------------------
  static String formatUptime(unsigned long ms) {
    unsigned long totalSec = ms / 1000UL;
    unsigned long minutes = totalSec / 60UL;
    unsigned long seconds = totalSec % 60UL;

    String s;
    if (minutes > 0) {
      s += String(minutes);
      s += F(" phút ");
      if (seconds < 10) {
        s += F("0");
      }
    }
    s += String(seconds);
    s += F(" giây");
    return s;
  }
};

#endif // TELEGRAM_ALERT_H
