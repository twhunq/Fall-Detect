/* ==========================================================================
 * device_identity.h
 * --------------------------------------------------------------------------
 * Lop DINH DANH va XAC THUC cua thiet bi. Cho phep phat hanh MOT ban firmware
 * cho nhieu nguoi dung ma app van biet dau la may cua ai, va tu choi duoc
 * thiet bi khong phai do minh lam ra.
 *
 * --------------------------------------------------------------------------
 * BA LOP DINH DANH
 *
 *   1. LOP SAN PHAM  : BLE_SERVICE_UUID trong ble_alert.h.
 *                      Y nghia: "day la thiet bi do toi lam". Khong bi mat,
 *                      chi de app loc bot khi quet.
 *
 *   2. LOP CA THE    : dia chi MAC 6 byte nam trong efuse cua chip, nha san
 *                      xuat ghi cung, duy nhat tren toan the gioi va KHONG
 *                      mat khi nap lai firmware. Rut gon thanh ma may dang
 *                      "CBC-7A3F91" (3 byte cuoi cua MAC).
 *
 *                      VI SAO KHONG TU SINH SO ROI LUU NVS: xoa flash la mat
 *                      so, may thanh thiet bi khac trong mat app.
 *
 *                      VI SAO KHONG DUNG TEN BLE: ca lo hang cung ten, hai nha
 *                      canh nhau la app bat nham may cua nhau.
 *
 *   3. LOP RANG BUOC : app luu ma may da ghep, sau do chi noi dung may do.
 *
 * --------------------------------------------------------------------------
 * XAC THUC: HOI - DAP (CHALLENGE / RESPONSE)
 *
 * Loc theo UUID chi chong NHAM chu khong chong GIA: ai doc duoc ma nguon cung
 * phat quang ba duoc dung bo UUID do. Nen phai them mot buoc hoi dap:
 *
 *   - Moi may co mot khoa rieng 32 byte:
 *         device_key = HMAC-SHA256(MASTER_KEY, mac_6_byte)
 *
 *   - Khoa nay duoc IN THANH MA QR DAN TREN VO MAY. App lay khoa bang cach
 *     quet QR luc ghep. Nho vay MASTER_KEY khong bao gio nam trong app - giai
 *     nen file APK ra cung khong tim thay gi.
 *
 *   - Luc ghep: app sinh mot chuoi ngau nhien (nonce), ghi vao dac tinh AUTH.
 *     Firmware tra ve HMAC-SHA256(device_key, nonce) cat lay 16 byte dau. App
 *     tu tinh lai bang khoa doc duoc tu QR roi so. Khop = may that.
 *
 *   - Nonce moi mot lan nen ke nghe len goi tin cu khong dung lai duoc
 *     (chong replay).
 *
 * KHOA NAM O DAU TRONG MAY: trong NVS, vung "cbn" / khoa "dkey". Cach nap xem
 * device_secrets.h. Uu tien doc tu NVS; chi khi NVS trong VA firmware co bien
 * dich kem MASTER_KEY thi moi tu suy ra roi luu lai.
 * ========================================================================== */

#ifndef DEVICE_IDENTITY_H
#define DEVICE_IDENTITY_H

#include <Arduino.h>
#include <Preferences.h>
#include <esp_system.h>
#include <mbedtls/md.h>

// esp_read_mac() nam o esp_system.h tren IDF 4.x va chuyen sang esp_mac.h ke
// tu IDF 5.0. Kiem tra su ton tai de build duoc tren ca hai doi framework.
#if defined(__has_include)
#if __has_include(<esp_mac.h>)
#include <esp_mac.h>
#endif
#endif

#if __has_include("device_secrets.h")
#include "device_secrets.h"
#endif

// ==========================================================================
// LOAI THIET BI
// --------------------------------------------------------------------------
// Thiet bi nay luon la CAMERA: ESP32-S3 lam cau noi cho camera K230. Loai may
// duoc nhet vao goi tin quang ba BLE de app xep dung muc ngay luc quet, chua
// can ket noi vao hoi.
// ==========================================================================
#define DEVICE_TYPE_CAMERA 2

#ifndef DEVICE_TYPE
#define DEVICE_TYPE DEVICE_TYPE_CAMERA
#endif

// Tien to ma may, in tren vo.
#ifndef DEVICE_ID_PREFIX
#define DEVICE_ID_PREFIX "CBC"
#endif

// Vung NVS rieng cua de tai. Ten vung toi da 15 ky tu.
#define DEVICE_NVS_NAMESPACE "cbn"
#define DEVICE_NVS_KEY_DKEY "dkey"

#define DEVICE_KEY_LEN 32      // HMAC-SHA256 sinh ra 32 byte
#define DEVICE_AUTH_TAG_LEN 16 // cat 16 byte dau cho vua goi tin BLE

// Do dai toi da mot lenh nap khoa qua Serial ("PROVF " + 64 ky tu + du).
#define DEVICE_CMD_MAX 80

// ==========================================================================
class DeviceIdentity {
public:
  DeviceIdentity() : _lenLenh(0), _ready(false), _hasKey(false) {
    _lenh[0] = '\0';
    memset(_mac, 0, sizeof(_mac));
    memset(_key, 0, sizeof(_key));
    _id[0] = '\0';
  }

  // ------------------------------------------------------------------------
  // Doc MAC, dung ma may, nap khoa rieng.
  //
  // Ham nay KHONG BAO GIO treo. Khong co khoa thi thiet bi van chay va van
  // canh bao duoc qua BLE/Telegram, chi la app se tu choi ghep vi khong xac
  // thuc duoc.
  // ------------------------------------------------------------------------
  bool begin() {
    // ---- 1. Doc dia chi MAC tu efuse ----
    if (esp_read_mac(_mac, ESP_MAC_WIFI_STA) != ESP_OK) {
      Serial.println(F("[ID] [LOI] Khong doc duoc dia chi MAC tu efuse."));
      return false;
    }

    // ---- 2. Dung ma may tu 3 byte cuoi ----
    // 3 byte dau la ma hang, con nao cung giong nhau nen bo di cho ma ngan.
    snprintf(_id, sizeof(_id), DEVICE_ID_PREFIX "-%02X%02X%02X", _mac[3],
             _mac[4], _mac[5]);

    // ---- 3. Nap khoa rieng ----
    _hasKey = _napKhoa();
    _ready = true;

    Serial.print(F("[ID] Ma may: "));
    Serial.print(_id);
    Serial.print(F("  MAC: "));
    Serial.println(macString());
    if (!_hasKey) {
      Serial.println(F("[ID] [CANH BAO] Chua co khoa rieng - app se khong ghep"));
      Serial.println(F("[ID]            duoc. Xem device_secrets.h de biet cach nap."));
    }
    return true;
  }

  bool isReady() const { return _ready; }
  bool hasKey() const { return _hasKey; }

  /// Ma may in tren vo, vi du "CBC-7A3F91". Cung la ten BLE khi phat quang ba.
  const char *id() const { return _id; }

  /// Loai may trong goi tin quang ba (2 = camera). App dung de xep vao dung muc.
  uint8_t loai() const { return static_cast<uint8_t>(DEVICE_TYPE); }

  /// 6 byte MAC tho, de nhet vao goi tin quang ba cho app doc duoc ma khong
  /// can ket noi.
  const uint8_t *macBytes() const { return _mac; }

  String macString() const {
    char buf[18];
    snprintf(buf, sizeof(buf), "%02X:%02X:%02X:%02X:%02X:%02X", _mac[0], _mac[1],
             _mac[2], _mac[3], _mac[4], _mac[5]);
    return String(buf);
  }

  // ------------------------------------------------------------------------
  // Tra loi cau hoi xac thuc cua app.
  //
  // nonce : chuoi ngau nhien app vua ghi xuong dac tinh AUTH.
  // Tra ve: 16 byte dau cua HMAC-SHA256(device_key, nonce), viet dang HEX
  //         hoa, tong cong 32 ky tu.
  //
  // Chuoi rong nghia la may chua co khoa - app se tu choi ghep.
  // ------------------------------------------------------------------------
  String authResponse(const uint8_t *nonce, size_t nonceLen) const {
    if (!_hasKey || nonce == nullptr || nonceLen == 0) {
      return String();
    }
    uint8_t tag[DEVICE_KEY_LEN];
    if (!hmacSha256(_key, DEVICE_KEY_LEN, nonce, nonceLen, tag)) {
      return String();
    }
    return toHex(tag, DEVICE_AUTH_TAG_LEN);
  }

  String authResponse(const String &nonce) const {
    return authResponse(reinterpret_cast<const uint8_t *>(nonce.c_str()),
                        nonce.length());
  }

  // ------------------------------------------------------------------------
  // Ky mot ban tin gui len server relay.
  //
  // Relay giu MASTER_KEY trong bien moi truong nen tinh lai duoc khoa rieng
  // cua may tu ma may co trong request - khong phai luu khoa vao co so du
  // lieu. Ben goi nho kem moc thoi gian vao payload de goi tin cu khong dung
  // lai duoc.
  // ------------------------------------------------------------------------
  String signPayload(const String &payload) const {
    if (!_hasKey) {
      return String();
    }
    uint8_t tag[DEVICE_KEY_LEN];
    if (!hmacSha256(_key, DEVICE_KEY_LEN,
                    reinterpret_cast<const uint8_t *>(payload.c_str()),
                    payload.length(), tag)) {
      return String();
    }
    return toHex(tag, DEVICE_KEY_LEN);
  }

  // ------------------------------------------------------------------------
  // Nhan khoa rieng gui xuong qua Serial luc nap (cach A trong
  // device_secrets.h). Cong cu nap khoa tren may tinh sinh khoa, gui mot lan.
  //
  // Doi khoa la moi dien thoai da ghep truoc do deu mat quyen, nguoi dung
  // phai quet lai ma QR moi - nen chi goi khi that su can.
  // ------------------------------------------------------------------------
  bool napKhoaHex(const String &hex64) {
    uint8_t k[DEVICE_KEY_LEN];
    if (!fromHex(hex64, k, DEVICE_KEY_LEN)) {
      Serial.println(F("[ID] [LOI] Khoa phai la 64 ky tu HEX."));
      return false;
    }
    Preferences p;
    if (!p.begin(DEVICE_NVS_NAMESPACE, false)) {
      Serial.println(F("[ID] [LOI] Khong mo duoc NVS de luu khoa."));
      return false;
    }
    const size_t n = p.putBytes(DEVICE_NVS_KEY_DKEY, k, DEVICE_KEY_LEN);
    p.end();
    if (n != DEVICE_KEY_LEN) {
      Serial.println(F("[ID] [LOI] Ghi khoa vao NVS that bai."));
      return false;
    }
    memcpy(_key, k, DEVICE_KEY_LEN);
    _hasKey = true;
    Serial.println(F("[ID] [OK] Da luu khoa rieng vao NVS."));
    return true;
  }

  // ------------------------------------------------------------------------
  // PHUC VU NAP KHOA QUA SERIAL - goi trong loop()
  //
  // Cong cu nap khoa tren may tinh se: doc MAC -> tu sinh khoa rieng -> nap
  // firmware -> gui khoa xuong qua day -> in ma QR de dan len vo.
  //
  // Nho vay MASTER_KEY chi ton tai tren may tinh cua nguoi lam ra thiet bi,
  // KHONG nam trong firmware. Ke nao do doc duoc flash cua mot may cung chi
  // co khoa cua dung may do, khong gia mao duoc ca lo hang.
  //
  // Cac lenh (ket thuc bang xuong dong):
  //     WHOAMI            -> ID|<ma_may>|<MAC>|<loai>|<da_co_khoa 0/1>
  //     PROV <64 ky tu>   -> nap khoa, chi khi may CHUA co khoa
  //     PROVF <64 ky tu>  -> nap de len khoa cu (F = force)
  //
  // Ham nay khong bao gio chan luong chinh: khong co ky tu nao thi thoat ngay.
  // ------------------------------------------------------------------------
  void phucVuSerial() {
    while (Serial.available() > 0) {
      const int c = Serial.read();
      if (c < 0) {
        break;
      }
      if (c == '\n' || c == '\r') {
        if (_lenLenh > 0) {
          _lenh[_lenLenh] = '\0';
          _xuLyLenh(_lenh);
          _lenLenh = 0;
        }
        continue;
      }
      if (_lenLenh >= DEVICE_CMD_MAX) {
        _lenLenh = 0; // lenh qua dai = rac, vut ca dong
        continue;
      }
      _lenh[_lenLenh++] = static_cast<char>(c);
    }
  }

  // ------------------------------------------------------------------------
  // HMAC-SHA256 dung mbedtls co san trong ESP-IDF - dung tinh than "khong
  // them thu vien ngoai" cua project.
  // ------------------------------------------------------------------------
  static bool hmacSha256(const uint8_t *key, size_t keyLen, const uint8_t *data,
                         size_t dataLen, uint8_t out[DEVICE_KEY_LEN]) {
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (info == nullptr) {
      return false;
    }
    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    // Tham so 1 = bat che do HMAC (0 la bam thuong, khong co khoa).
    const bool ok = mbedtls_md_setup(&ctx, info, 1) == 0 &&
                    mbedtls_md_hmac_starts(&ctx, key, keyLen) == 0 &&
                    mbedtls_md_hmac_update(&ctx, data, dataLen) == 0 &&
                    mbedtls_md_hmac_finish(&ctx, out) == 0;
    mbedtls_md_free(&ctx);
    return ok;
  }

  static String toHex(const uint8_t *buf, size_t len) {
    static const char kBang[] = "0123456789ABCDEF";
    String s;
    s.reserve(len * 2);
    for (size_t i = 0; i < len; i++) {
      s += kBang[buf[i] >> 4];
      s += kBang[buf[i] & 0x0F];
    }
    return s;
  }

private:
  // ------------------------------------------------------------------------
  void _xuLyLenh(const char *lenh) {
    if (strcmp(lenh, "WHOAMI") == 0) {
      Serial.print(F("ID|"));
      Serial.print(_id);
      Serial.print('|');
      Serial.print(macString());
      Serial.print('|');
      Serial.print(static_cast<int>(DEVICE_TYPE));
      Serial.print('|');
      Serial.println(_hasKey ? '1' : '0');
      return;
    }

    const bool epGhi = (strncmp(lenh, "PROVF ", 6) == 0);
    const bool binhThuong = (strncmp(lenh, "PROV ", 5) == 0);
    if (!epGhi && !binhThuong) {
      return; // khong phai lenh cua ta, im lang de khong lam nhieu log
    }

    // Da co khoa roi ma nap de len la moi dien thoai da ghep truoc do deu mat
    // quyen, nguoi dung phai quet lai ma QR moi - nen bat phai noi ro y dinh
    // bang lenh PROVF thay vi lo tay mot cai la hong ca lo hang da ban ra.
    if (_hasKey && !epGhi) {
      Serial.println(F("PROV_ERR|DA_CO_KHOA"));
      return;
    }

    if (napKhoaHex(String(lenh + (epGhi ? 6 : 5)))) {
      Serial.print(F("PROV_OK|"));
      Serial.println(_id);
    } else {
      Serial.println(F("PROV_ERR|KHOA_SAI"));
    }
  }

  // ------------------------------------------------------------------------
  bool _napKhoa() {
    // ---- Uu tien khoa da nam san trong NVS ----
    // Mo che do doc-ghi (false) de tao vung "cbn" lan dau ma khong in loi
    // [E][Preferences.cpp] nvs_open failed: NOT_FOUND tren Serial.
    Preferences p;
    if (p.begin(DEVICE_NVS_NAMESPACE, false)) {
      const size_t n = p.isKey(DEVICE_NVS_KEY_DKEY)
                           ? p.getBytes(DEVICE_NVS_KEY_DKEY, _key, DEVICE_KEY_LEN)
                           : 0;
      p.end();
      if (n == DEVICE_KEY_LEN) {
        Serial.println(F("[ID] Da nap khoa rieng tu NVS."));
        return true;
      }
    }

#ifdef DEVICE_MASTER_KEY
    // ---- Chua co thi suy ra tu MASTER_KEY roi luu lai (cach B) ----
    uint8_t master[DEVICE_KEY_LEN];
    if (!fromHex(String(DEVICE_MASTER_KEY), master, DEVICE_KEY_LEN)) {
      Serial.println(F("[ID] [LOI] DEVICE_MASTER_KEY phai la 64 ky tu HEX."));
      return false;
    }
    if (!hmacSha256(master, DEVICE_KEY_LEN, _mac, 6, _key)) {
      return false;
    }
    Preferences w;
    if (w.begin(DEVICE_NVS_NAMESPACE, false)) {
      w.putBytes(DEVICE_NVS_KEY_DKEY, _key, DEVICE_KEY_LEN);
      w.end();
    }
    Serial.println(F("[ID] Da suy ra khoa rieng tu MASTER_KEY va luu vao NVS."));
    return true;
#else
    return false;
#endif
  }

  // ------------------------------------------------------------------------
  static bool fromHex(const String &hex, uint8_t *out, size_t outLen) {
    if (hex.length() != outLen * 2) {
      return false;
    }
    for (size_t i = 0; i < outLen; i++) {
      const int hi = _nibble(hex.charAt(i * 2));
      const int lo = _nibble(hex.charAt(i * 2 + 1));
      if (hi < 0 || lo < 0) {
        return false;
      }
      out[i] = static_cast<uint8_t>((hi << 4) | lo);
    }
    return true;
  }

  static int _nibble(char c) {
    if (c >= '0' && c <= '9') {
      return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
      return c - 'a' + 10;
    }
    if (c >= 'A' && c <= 'F') {
      return c - 'A' + 10;
    }
    return -1;
  }

  uint8_t _mac[6];
  char _id[16];
  uint8_t _key[DEVICE_KEY_LEN];

  /// Bo dem gom tung ky tu Serial thanh mot dong lenh nap khoa.
  char _lenh[DEVICE_CMD_MAX + 1];
  int _lenLenh;

  bool _ready;
  bool _hasKey;
};

#endif // DEVICE_IDENTITY_H
