/* ==========================================================================
 * device_config.h
 * --------------------------------------------------------------------------
 * Cau hinh chay duoc SUA TU APP, luu trong NVS (bo nho khong mat khi tat
 * dien) thay vi nam cung trong ma nguon.
 *
 * --------------------------------------------------------------------------
 * VI SAO PHAI CO FILE NAY
 *
 * Nguoi dung doi WiFi/Telegram khong the phai gui may lai nap chuong trinh.
 * App ghi cau hinh xuong may qua BLE (dac tinh CONFIG trong ble_alert.h),
 * firmware luu vao NVS va doc lai moi lan khoi dong. Mot ban firmware cho ca
 * lo hang.
 *
 * Cac #define WIFI_SSID/... trong device_secrets.h chi la GIA TRI MAC DINH cho
 * lan chay dau tien khi NVS con trong.
 *
 * --------------------------------------------------------------------------
 * AI DUOC PHEP GHI CAU HINH
 *
 * Chi dien thoai da vuot qua buoc hoi - dap trong device_identity.h moi ghi
 * duoc. Neu khong, hang xom trong tam song BLE co the ghi de WiFi va chat id
 * - canh bao nga se bay sang dien thoai nguoi la. Viec kiem tra do nam trong ble_alert.h.
 *
 * MAT KHAU WIFI NAM TRONG NVS O DANG CHUA MA HOA. Ai thao may ra doc duoc
 * flash la lay duoc. Muon kin hon thi phai bat NVS encryption cua ESP-IDF -
 * ngoai pham vi de tai nay, nhung nen ghi ro trong bao cao.
 * ========================================================================== */

#ifndef DEVICE_CONFIG_H
#define DEVICE_CONFIG_H

#include <Arduino.h>
#include <Preferences.h>

// Dung chung vung NVS voi device_identity.h. Ten vung toi da 15 ky tu.
#ifndef DEVICE_NVS_NAMESPACE
#define DEVICE_NVS_NAMESPACE "cbn"
#endif

// Ten khoa trong NVS cung bi gioi han 15 ky tu nen viet tat.
#define CFG_KEY_SSID "ssid"
#define CFG_KEY_PASS "pass"
#define CFG_KEY_TOKEN "tgtok"
#define CFG_KEY_CHAT "tgchat"
#define CFG_KEY_HOME "home"
#define CFG_KEY_RELAY "relay"

// ==========================================================================
// MA NHA (homeId) - KHOA DE GOP CANH BAO
// --------------------------------------------------------------------------
// He thong co hai nguon phat hien nga cung lam viec: vong deo tren tay va
// camera K230. Hai nguon nay se phat hien CUNG MOT cu nga cach nhau chua toi
// mot giay, va neu de moi ben tu gui thi nguoi than nhan hai tin cho mot cu
// nga - vua roi loan vua lam ho quen di cai nao that.
//
// CACH LAM SAI: bao mot ben im lang khi ben kia da bao. Hai ben phat hien gan
// nhu dong thoi nen ca hai deu tuong minh la nguoi bao dau tien - van hai tin.
// Con neu ben nao cung cho ben kia bao truoc thi co luc KHONG AI BAO CA.
//
// CACH LAM DUNG: nguon nao cung cu bao day du, kem theo ma nha va moc thoi
// gian. Ben nhan (app va server relay) gop moi bao cao roi trong cung mot cua
// so thoi gian cua CUNG MOT NHA thanh MOT su kien nga duy nhat:
//     - bao cao den truoc  -> gui tin canh bao ngay
//     - bao cao den sau    -> khong gui tin moi, chi bo sung vao su kien da
//                             co ("ca camera lan vong deo cung xac nhan")
//
// Nho vay khong nhan doi tin, ma cung khong vut di thong tin: hai nguon cung
// xac nhan la tin hieu rat manh - do chinh la ly do lap hai thiet bi.
//
// Ma nha do app sinh ra luc ghep thiet bi dau tien, roi ghi xuong moi thiet
// bi trong nha. Hai may khac ma nha la hai su kien rieng biet, khong gop.
// ==========================================================================

// Gioi han do dai de mot goi tin BLE hong khong lam tran bo nho.
#define CFG_MAX_FIELD_LEN 128

// ==========================================================================
class DeviceConfig {
public:
  DeviceConfig() {}

  // ------------------------------------------------------------------------
  // Nap cau hinh tu NVS. Truong nao NVS chua co thi lay gia tri mac dinh
  // truyen vao (cac #define trong device_secrets.h).
  //
  // Truyen nullptr cho truong nao khong co mac dinh.
  // ------------------------------------------------------------------------
  bool begin(const char *ssidMacDinh, const char *matKhauMacDinh,
             const char *tokenMacDinh, const char *chatIdMacDinh) {
    Preferences p;
    if (p.begin(DEVICE_NVS_NAMESPACE, false)) {
      _ssid = p.isKey(CFG_KEY_SSID) ? p.getString(CFG_KEY_SSID, String()) : String();
      _matKhau = p.isKey(CFG_KEY_PASS) ? p.getString(CFG_KEY_PASS, String()) : String();
      _token = p.isKey(CFG_KEY_TOKEN) ? p.getString(CFG_KEY_TOKEN, String()) : String();
      _chatId = p.isKey(CFG_KEY_CHAT) ? p.getString(CFG_KEY_CHAT, String()) : String();
      _maNha = p.isKey(CFG_KEY_HOME) ? p.getString(CFG_KEY_HOME, String()) : String();
      _relay = p.isKey(CFG_KEY_RELAY) ? p.getString(CFG_KEY_RELAY, String()) : String();
      p.end();
    }

    // Chua co gi trong NVS thi dung mac dinh bien dich san.
    if (_ssid.isEmpty() && ssidMacDinh != nullptr) {
      _ssid = ssidMacDinh;
    }
    if (_matKhau.isEmpty() && matKhauMacDinh != nullptr) {
      _matKhau = matKhauMacDinh;
    }
    if (_token.isEmpty() && tokenMacDinh != nullptr) {
      _token = tokenMacDinh;
    }
    if (_chatId.isEmpty() && chatIdMacDinh != nullptr) {
      _chatId = chatIdMacDinh;
    }

    Serial.print(F("[CFG] WiFi: "));
    Serial.print(_ssid.isEmpty() ? String(F("(chua dat)")) : _ssid);
    Serial.print(F("  Telegram: "));
    Serial.print(daCauHinhTelegram() ? F("da co token/chat id") : F("(chua dat)"));
    Serial.print(F("  Ma nha: "));
    Serial.println(_maNha.isEmpty() ? String(F("(chua ghep)")) : _maNha);
    return true;
  }

  const String &ssid() const { return _ssid; }
  const String &matKhau() const { return _matKhau; }
  const String &token() const { return _token; }
  const String &chatId() const { return _chatId; }

  /// Ma nha - khoa de app va relay gop canh bao cua vong deo voi camera.
  const String &maNha() const { return _maNha; }

  /// Dia chi server relay, vi du "https://canhbaonga.vercel.app".
  /// Rong nghia la chua dung relay - thiet bi quay ve goi thang Telegram.
  const String &relayUrl() const { return _relay; }

  bool daCauHinhRelay() const {
    return !_relay.isEmpty() && !_maNha.isEmpty();
  }

  bool daCauHinhWiFi() const { return !_ssid.isEmpty(); }

  bool daCauHinhTelegram() const {
    return !_token.isEmpty() && !_chatId.isEmpty() &&
           _token != F("DIEN_TOKEN_BOT_VAO_DAY") &&
           _chatId != F("DIEN_CHAT_ID_VAO_DAY");
  }

  // ------------------------------------------------------------------------
  // Nhan cau hinh app ghi xuong qua BLE.
  //
  // Dinh dang, cung tinh than gach dung nhu cac ban tin khac cua de tai:
  //     CFG|<ssid>|<mat_khau>|<token>|<chat_id>|<ma_nha>|<dia_chi_relay>
  //
  // De TRONG mot truong nghia la GIU NGUYEN gia tri cu - nho vay app doi
  // moi chat id ma khong phai bat nguoi dung go lai mat khau WiFi.
  //
  // Thieu han truong o cuoi cung khong sao (ban tin 4 truong kieu cu van
  // chay): thieu la giu nguyen, y het nhu de trong.
  //
  // Tra ve true neu da ghi duoc xuong NVS.
  // ------------------------------------------------------------------------
  bool capNhatTuChuoi(const String &payload) {
    if (!payload.startsWith(F("CFG|"))) {
      Serial.println(F("[CFG] [LOI] Ban tin cau hinh sai dinh dang."));
      return false;
    }

    // Tach toi da 6 truong. Truong cuoi KHONG lay het phan con lai ma van
    // tach theo dau gach: neu khong, mot ban tin thua dau gach se lam ma nha
    // dinh theo rac phia sau ma khong bao loi gi.
    String truong[6];
    int batDau = 4; // bo qua "CFG|"
    int soTruong = 0;
    while (soTruong < 6 && batDau <= static_cast<int>(payload.length())) {
      const int viTri = payload.indexOf('|', batDau);
      if (viTri < 0) {
        truong[soTruong] = payload.substring(batDau);
        soTruong++;
        break;
      }
      truong[soTruong] = payload.substring(batDau, viTri);
      soTruong++;
      batDau = viTri + 1;
    }

    for (int i = 0; i < soTruong; i++) {
      truong[i].trim();
      if (truong[i].length() > CFG_MAX_FIELD_LEN) {
        Serial.println(F("[CFG] [LOI] Mot truong cau hinh qua dai."));
        return false;
      }
    }

    String *dich[6] = {&_ssid,   &_matKhau, &_token,
                       &_chatId, &_maNha,   &_relay};
    for (int i = 0; i < soTruong; i++) {
      if (!truong[i].isEmpty()) {
        *dich[i] = truong[i];
      }
    }

    return _luu();
  }

private:
  // ------------------------------------------------------------------------
  bool _luu() {
    Preferences p;
    if (!p.begin(DEVICE_NVS_NAMESPACE, false)) {
      Serial.println(F("[CFG] [LOI] Khong mo duoc NVS de ghi cau hinh."));
      return false;
    }
    p.putString(CFG_KEY_SSID, _ssid);
    p.putString(CFG_KEY_PASS, _matKhau);
    p.putString(CFG_KEY_TOKEN, _token);
    p.putString(CFG_KEY_CHAT, _chatId);
    p.putString(CFG_KEY_HOME, _maNha);
    p.putString(CFG_KEY_RELAY, _relay);
    p.end();

    Serial.print(F("[CFG] [OK] Da luu cau hinh moi. WiFi: "));
    Serial.println(_ssid);
    return true;
  }

  String _ssid;
  String _matKhau;
  String _token;
  String _chatId;
  String _maNha;
  String _relay;
};

#endif // DEVICE_CONFIG_H
