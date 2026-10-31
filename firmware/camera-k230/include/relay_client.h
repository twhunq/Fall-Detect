/* ==========================================================================
 * relay_client.h
 * --------------------------------------------------------------------------
 * Bao nga len SERVER RELAY thay vi goi thang Bot API cua Telegram.
 *
 * --------------------------------------------------------------------------
 * VI SAO KHONG GOI THANG TELEGRAM NUA
 *
 * Goi thang thi moi thiet bi phai giu token bot trong bo nho. Ma co token la
 * doc duoc getUpdates - tuc la doc trom duoc tin nhan cua MOI gia dinh dung
 * chung con bot do, va nhan tin mao danh bot cho bat ky ai da bam Start.
 * Ai thao mot chiec may ra doc flash la co token cua ca he thong.
 *
 * Qua relay thi token chi nam tren server. Thiet bi chi giu khoa rieng cua
 * chinh no, lo ra cung chi anh huong dung chiec may do.
 *
 * VA QUAN TRONG HON: relay la cho DUY NHAT nhin thay ca bao cao cua vong deo
 * lan bao cao cua camera, nen no gop duoc hai bao cao ve cung mot cu nga
 * thanh MOT tin. Goi thang thi nguoi than nhan hai tin cho mot lan nga.
 *
 * --------------------------------------------------------------------------
 * CACH KY
 *
 *     chuoi_ky = "<moc_thoi_gian_ms>.<noi_dung_JSON>"
 *     X-Sig    = HMAC-SHA256(khoa_rieng, chuoi_ky)   dang HEX hoa
 *
 * Moc thoi gian nam TRONG phan duoc ky nen khong sua duoc, va server tu choi
 * request cu qua 120 giay. Ke ghi lai duoc mot goi tin hop le cung khong phat
 * lai duoc sau do de dung canh bao gia.
 *
 * PHAI CO GIO THAT: chu ky dung moc thoi gian nen dong ho phai duoc dong bo
 * NTP truoc. telegram_alert.h da lam viec do trong syncTime().
 *
 * --------------------------------------------------------------------------
 * KHONG BAO GIO CHAN LUONG CHINH QUA LAU
 *
 * Toan bo ham co gioi han thoi gian cho. Relay chet, het han muc, mat mang -
 * app tren dien thoai van nhan duoc canh bao qua BLE. Duong mang chi la
 * duong PHU.
 * ========================================================================== */

#ifndef RELAY_CLIENT_H
#define RELAY_CLIENT_H

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <time.h>

#include "device_config.h"
#include "device_identity.h"

#define RELAY_TIMEOUT_MS 8000UL

// Ban tin tra ve chi vai tram byte. Doc qua muc nay la co gi do sai, dung lai
// chu dung doc mai cho toi khi het bo nho.
#define RELAY_MAX_RESPONSE 1024

// ==========================================================================
/// Ket qua mot lan bao ngã len relay.
struct RelayKetQua {
  bool ok = false;

  /// Ma su kien do server cap. Camera dinh anh bang chung vao ma nay.
  String maSuKien;

  /// Phieu tai anh dung MOT lan, song 5 phut.
  ///
  /// Nho phieu nay ma K230 KHONG can giu khoa rieng cua thiet bi: con ESP32
  /// ky request, lay phieu ve roi dua cho K230 qua day UART.
  String phieuAnh;

  /// Server da gop bao cao nay vao mot su kien dang mo (nguon kia bao truoc).
  bool daGop = false;
};

// ==========================================================================
class RelayClient {
public:
  RelayClient() : _id(nullptr), _cfg(nullptr) {}

  void begin(DeviceIdentity *id, DeviceConfig *cfg) {
    _id = id;
    _cfg = cfg;
  }

  bool sanSang() const {
    return _id != nullptr && _cfg != nullptr && _cfg->daCauHinhRelay() &&
           _id->hasKey() && WiFi.status() == WL_CONNECTED;
  }

  // ------------------------------------------------------------------------
  // Bao mot cu nga len relay.
  //
  // nguon: "band" cho vong deo, "cam" cho camera.
  // ------------------------------------------------------------------------
  RelayKetQua baoNga(const char *nguon, float doTinCay,
                    const char *reportId = nullptr, unsigned long ageMs = 0) {
    RelayKetQua kq;

    if (!sanSang()) {
      return kq;
    }

    // ---- Moc thoi gian that ----
    const time_t giay = time(nullptr);
    if (giay < 1700000000) {
      // Chua dong bo NTP xong. Ky bang gio sai thi server chac chan tu choi,
      // gui di chi ton thoi gian va lam cham duong bao khac.
      Serial.println(F("[RELAY] Chua co gio that, bo qua lan bao nay."));
      return kq;
    }

    char moc[16];
    snprintf(moc, sizeof(moc), "%llu",
             static_cast<unsigned long long>(giay) * 1000ULL);

    // ---- Noi dung ----
    String than = F("{\"home\":\"");
    than += _cfg->maNha();
    than += F("\",\"conf\":");
    than += String(doTinCay * 100.0f, 1);
    than += F(",\"source\":\"");
    than += nguon;
    than += '"';
    if (reportId != nullptr) {
      than += F(",\"reportId\":\"");
      than += reportId;
      than += '"';
    }
    than += F(",\"ageMs\":");
    than += String(ageMs);
    than += '}';

    String chuoiKy = String(moc);
    chuoiKy += '.';
    chuoiKy += than;
    const String chuKy = _id->signPayload(chuoiKy);
    if (chuKy.isEmpty()) {
      return kq;
    }

    // ---- Tach dia chi server ----
    String host;
    uint16_t cong = 443;
    String duongDan;
    if (!_tachUrl(_cfg->relayUrl(), host, cong, duongDan)) {
      Serial.println(F("[RELAY] [LOI] Dia chi relay khong hop le."));
      return kq;
    }
    duongDan += F("/api/alert");

    // ---- Gui ----
    WiFiClientSecure client;
    // Bo qua kiem tra chung chi CA, giong telegram_alert.h. Danh doi: khong
    // phai nhung chung chi goc vao firmware (chung co han su dung, het han la
    // he thong chet lang). Noi dung gui di da duoc ky nen khong sua duoc tren
    // duong truyen; ke nghe len chi biet "co nguoi nga".
    client.setInsecure();
    client.setHandshakeTimeout(RELAY_TIMEOUT_MS / 1000);
    client.setTimeout(RELAY_TIMEOUT_MS / 1000);

    if (!client.connect(host.c_str(), cong)) {
      Serial.println(F("[RELAY] [LOI] Khong mo duoc ket noi toi relay."));
      return kq;
    }

    client.print(F("POST "));
    client.print(duongDan);
    client.print(F(" HTTP/1.1\r\nHost: "));
    client.print(host);
    client.print(F("\r\nContent-Type: application/json"));
    client.print(F("\r\nX-Device: "));
    client.print(_id->id());
    client.print(F("\r\nX-Mac: "));
    client.print(_id->macString());
    client.print(F("\r\nX-Ts: "));
    client.print(moc);
    client.print(F("\r\nX-Sig: "));
    client.print(chuKy);
    client.print(F("\r\nContent-Length: "));
    client.print(than.length());
    client.print(F("\r\nConnection: close\r\n\r\n"));
    client.print(than);

    // ---- Doc tra loi ----
    const String traLoi = _docTraLoi(client);
    client.stop();

    if (!traLoi.startsWith("HTTP/1.1 200 ") &&
        !traLoi.startsWith("HTTP/1.0 200 ")) {
      Serial.println(F("[RELAY] [LOI] Relay khong tra loi."));
      return kq;
    }

    kq.maSuKien = _layChuoi(traLoi, "eventId");
    kq.phieuAnh = _layChuoi(traLoi, "uploadToken");
    kq.daGop = traLoi.indexOf(F("\"merged\":true")) >= 0;
    kq.ok = !kq.maSuKien.isEmpty();

    if (kq.ok) {
      Serial.print(F("[RELAY] [OK] Da bao len relay. Su kien: "));
      Serial.print(kq.maSuKien);
      Serial.println(kq.daGop ? F(" (gop vao su kien dang mo)") : F(" (moi)"));
    } else {
      Serial.print(F("[RELAY] [LOI] Relay tu choi: "));
      Serial.println(traLoi);
    }
    return kq;
  }

private:
  // ------------------------------------------------------------------------
  static bool _tachUrl(const String &url, String &host, uint16_t &cong,
                       String &duongDan) {
    int i = url.indexOf(F("://"));
    if (i < 0) {
      return false;
    }
    const String giaoThuc = url.substring(0, i);
    if (giaoThuc != F("https")) return false;
    cong = 443;

    String conLai = url.substring(i + 3);
    const int gach = conLai.indexOf('/');
    if (gach >= 0) {
      duongDan = conLai.substring(gach);
      conLai = conLai.substring(0, gach);
    } else {
      duongDan = "";
    }
    // Bo dau gach cuoi, neu khong duong dan se thanh "//api/alert".
    while (duongDan.endsWith("/")) {
      duongDan.remove(duongDan.length() - 1);
    }

    const int haiCham = conLai.indexOf(':');
    if (haiCham >= 0) {
      cong = static_cast<uint16_t>(conLai.substring(haiCham + 1).toInt());
      conLai = conLai.substring(0, haiCham);
    }

    host = conLai;
    return host.length() > 0;
  }

  // ------------------------------------------------------------------------
  static String _docTraLoi(WiFiClientSecure &client) {
    String tat;
    const unsigned long batDau = millis();
    while ((client.connected() || client.available()) && millis() - batDau < RELAY_TIMEOUT_MS) {
      while (client.available()) {
        tat += static_cast<char>(client.read());
        if (tat.length() >= RELAY_MAX_RESPONSE) {
          return tat;
        }
      }
      delay(10);
    }
    return tat;
  }

  // ------------------------------------------------------------------------
  // Rut mot gia tri chuoi ra khoi JSON.
  //
  // Tu tach thay vi dung thu vien JSON: ban tin tra ve co dung ba truong va
  // deu la chuoi phang, khong dang de keo them mot thu vien vao firmware.
  static String _layChuoi(const String &json, const char *khoa) {
    String can = "\"";
    can += khoa;
    can += "\":\"";
    const int i = json.indexOf(can);
    if (i < 0) {
      return String();
    }
    const int batDau = i + can.length();
    const int ketThuc = json.indexOf('"', batDau);
    if (ketThuc < 0) {
      return String();
    }
    return json.substring(batDau, ketThuc);
  }

  DeviceIdentity *_id;
  DeviceConfig *_cfg;
};

#endif // RELAY_CLIENT_H
