/* ==========================================================================
 * ble_alert.h
 * --------------------------------------------------------------------------
 * Phat canh bao qua Bluetooth BLE toi app tren dien thoai, song song voi
 * Telegram/relay.
 *
 * VI SAO CAN LOP NAY:
 *   Telegram/relay chi hoat dong khi co WiFi. BLE khong can mang: la song
 *   truc tiep tu thiet bi sang dien thoai, va ve sau app dung GPS va song nha
 *   mang CUA CHINH DIEN THOAI de bao cho nguoi than (SMS di qua kenh bao hieu
 *   cua nha mang, het 4G van gui duoc). Khong can module GPS/SIM.
 *
 * KIEN TRUC BLE:
 *   ESP32-S3 la BLE Server (peripheral), dien thoai la Client. Dich vu gom:
 *
 *     - ALERT  : ban tin canh bao, gui bang NOTIFY.
 *                Dinh dang:  FALL|<do_tin_cay>|<uptime_ms>
 *                Vi du:      FALL|87.3|254120
 *
 *     - STATUS : nhip tim, NOTIFY moi 10 giay.
 *                Dinh dang:  ALIVE|<uptime_ms>|<co_wifi 0/1>
 *
 *     - AUTH, CONFIG, INFO: xem cac ham/hang so ben duoi.
 *
 *   Dinh dang gach dung thay vi JSON de app tach chuoi cho don gian.
 *
 * LUU Y: BLE chi voi khoang 10-30m trong nha, tuy tuong va vat can.
 * ========================================================================== */

#ifndef BLE_ALERT_H
#define BLE_ALERT_H

#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <esp_gap_ble_api.h>

#include "device_config.h"
#include "device_identity.h"

// ==========================================================================
// CAU HINH
// ==========================================================================

// Ten quang ba that lay tu ma may (MAC, xem device_identity.h), vi du
// "CBC-7A3F91", de hai nha canh nhau khong bat nham may cua nhau. Chuoi duoi
// day chi dung khi khong doc duoc MAC.
#define BLE_DEVICE_NAME_FALLBACK "CanhBaoNga-00"

// Ma nha san xuat trong goi tin quang ba. 0xFFFF la ma danh rieng cho thu
// nghiem/noi bo theo Bluetooth SIG - dung duoc ma khong phai dang ky.
#define BLE_MANUFACTURER_ID 0xFFFF

// UUID rieng cua de tai. App Flutter phai dung DUNG cac chuoi nay, neu doi o
// day thi phai doi ca ben app (file lib/config.dart).
#define BLE_SERVICE_UUID "a8f3d100-1b2c-4e5f-9a7b-3c6d8e0f1234"
#define BLE_CHAR_ALERT_UUID "a8f3d101-1b2c-4e5f-9a7b-3c6d8e0f1234"
#define BLE_CHAR_STATUS_UUID "a8f3d102-1b2c-4e5f-9a7b-3c6d8e0f1234"
// AUTH   : app ghi chuoi ngau nhien xuong, doc lai loi giai de biet may that.
// CONFIG : app ghi WiFi/Telegram xuong, chi nhan sau khi da xac thuc.
#define BLE_CHAR_AUTH_UUID "a8f3d103-1b2c-4e5f-9a7b-3c6d8e0f1234"
#define BLE_CHAR_CONFIG_UUID "a8f3d104-1b2c-4e5f-9a7b-3c6d8e0f1234"
// INFO : mot dong mo ta thiet bi. Cau noi camera dung de bao dia chi xem hinh
//        trong mang nha (do router cap, hay doi nen khong bat go tay):
//            CAM|192.168.1.50|81|/stream
#define BLE_CHAR_INFO_UUID "a8f3d105-1b2c-4e5f-9a7b-3c6d8e0f1234"

// Chuoi ngau nhien app gui xuong phai du dai, neu khong ke tan cong co the
// thu het moi kha nang roi ghi lai bang tra loi san.
#define BLE_AUTH_NONCE_MIN_LEN 8

// Muc cong suat phat BLE. Mac dinh cua thu vien chi khoang +3dBm; nang len
// +18dBm duoc them khoang 2-3 lan tam song.
//
// ESP32-S3 con ho tro toi ESP_PWR_LVL_P21, nhung KHONG dat mac dinh o do:
// cang phat manh cang rut dong dot ngot lon, nguon yeu de sut ap -> reset.
//
// Cac muc dung duoc: P3, P6, P9, P12, P15, P18, P21.
// Neu thiet bi hay tu reset, ha xuong P9.
#define BLE_TX_POWER_LEVEL ESP_PWR_LVL_P18

// Chu ky gui nhip tim bao con song.
#define BLE_HEARTBEAT_INTERVAL_MS 10000UL

// Gui lai ban tin canh bao vai lan de chac chan app nhan duoc (goi tin BLE
// co the roi neu song yeu ngay dung luc do).
#define BLE_ALERT_REPEAT_COUNT 3
#define BLE_ALERT_REPEAT_GAP_MS 400UL

// ==========================================================================
// Theo doi trang thai ket noi cua dien thoai
// ==========================================================================
class BleConnectionTracker : public BLEServerCallbacks {
public:
  BleConnectionTracker()
      : connected(false), justDisconnected(false), daXacThuc(nullptr) {}

  void onConnect(BLEServer *server) override {
    (void)server;
    connected = true;
    // Moi ket noi phai xac thuc lai tu dau. Neu giu co hieu cu, mot dien
    // thoai la ket noi ngay sau dien thoai that se thua huong quyen ghi
    // cau hinh ma khong phai chung minh gi.
    if (daXacThuc != nullptr) {
      *daXacThuc = false;
    }
    Serial.println(F("[BLE] Dien thoai da ket noi."));
  }

  void onDisconnect(BLEServer *server) override {
    (void)server;
    connected = false;
    justDisconnected = true;
    if (daXacThuc != nullptr) {
      *daXacThuc = false;
    }
    Serial.println(F("[BLE] Dien thoai da ngat ket noi."));
  }

  volatile bool connected;
  volatile bool justDisconnected;

  /// Tro toi co hieu "phien nay da xac thuc" cua BleAlert, de xoa khi dut.
  volatile bool *daXacThuc;
};

// ==========================================================================
// Dac tinh AUTH - chung minh day la thiet bi that
//
// App ghi xuong mot chuoi ngau nhien (nonce). Firmware tinh
// HMAC-SHA256(khoa_rieng, nonce) roi dat lam gia tri cua chinh dac tinh do,
// app doc len va so voi ket qua no tu tinh bang khoa quet duoc tu ma QR.
//
// Khoa khong bao gio di qua song. Nonce moi moi lan nen ke nghe len goi tin
// cu khong dung lai duoc.
// ==========================================================================
class BleAuthCallbacks : public BLECharacteristicCallbacks {
public:
  BleAuthCallbacks(DeviceIdentity *id, volatile bool *co)
      : _id(id), _daXacThuc(co) {}

  void onWrite(BLECharacteristic *chr) override {
    if (_id == nullptr || chr == nullptr) {
      return;
    }
    const String nonce = String(chr->getValue().c_str());

    if (nonce.length() < BLE_AUTH_NONCE_MIN_LEN) {
      chr->setValue("ERR|NONCE_NGAN");
      Serial.println(F("[BLE] [AUTH] Chuoi ngau nhien qua ngan - tu choi."));
      return;
    }

    const String traLoi = _id->authResponse(nonce);
    if (traLoi.isEmpty()) {
      chr->setValue("ERR|CHUA_CO_KHOA");
      Serial.println(F("[BLE] [AUTH] May chua co khoa rieng - khong tra loi duoc."));
      return;
    }

    chr->setValue(traLoi.c_str());
    if (_daXacThuc != nullptr) {
      *_daXacThuc = true;
    }
    Serial.println(F("[BLE] [AUTH] Da tra loi cau hoi xac thuc."));
  }

private:
  DeviceIdentity *_id;
  volatile bool *_daXacThuc;
};

// ==========================================================================
// Dac tinh CONFIG - app ghi WiFi va Telegram xuong may
//
// Chi nhan khi phien hien tai DA xac thuc. Neu khong, bat cu ai trong tam
// song BLE cung doi duoc ten WiFi va chat id cua may nha nguoi khac - canh
// bao nga se bay sang dien thoai nguoi la.
// ==========================================================================
class BleConfigCallbacks : public BLECharacteristicCallbacks {
public:
  BleConfigCallbacks(DeviceConfig *cfg, volatile bool *co)
      : _cfg(cfg), _daXacThuc(co) {}

  void onWrite(BLECharacteristic *chr) override {
    if (_cfg == nullptr || chr == nullptr) {
      return;
    }

    if (_daXacThuc == nullptr || !*_daXacThuc) {
      chr->setValue("ERR|CHUA_XAC_THUC");
      Serial.println(F("[BLE] [CFG] Tu choi: phien nay chua xac thuc."));
      return;
    }

    const String payload = String(chr->getValue().c_str());
    if (_cfg->capNhatTuChuoi(payload)) {
      chr->setValue("OK");
      Serial.println(F("[BLE] [CFG] Da nhan cau hinh moi tu app."));
      Serial.println(F("[BLE] [CFG] Khoi dong lai may de dung WiFi moi."));
    } else {
      chr->setValue("ERR|SAI_DINH_DANG");
    }
  }

private:
  DeviceConfig *_cfg;
  volatile bool *_daXacThuc;
};

// ==========================================================================
class BleAlert {
public:
  BleAlert()
      : _server(nullptr), _alertChar(nullptr), _statusChar(nullptr),
        _authChar(nullptr), _configChar(nullptr), _infoChar(nullptr),
        _authCb(nullptr), _configCb(nullptr), _id(nullptr), _cfg(nullptr),
        _daXacThuc(false), _lastHeartbeat(0), _started(false), _lapConLai(0),
        _lanLapCuoi(0) {
    _alertPayload[0] = '\0';
  }

  // ------------------------------------------------------------------------
  // Khoi tao BLE va bat dau phat quang ba (advertising).
  //
  // id  : lop dinh danh da begin() truoc do - quyet dinh ten quang ba va cach
  //       tra loi cau hoi xac thuc cua app.
  // cfg : cau hinh nguoi dung, de app ghi WiFi/Telegram xuong. Truyen nullptr
  //       neu chua can tinh nang do.
  //
  // Ham nay KHONG BAO GIO treo. Neu BLE khong khoi tao duoc, he thong van
  // chay va van bao qua Telegram/relay.
  // ------------------------------------------------------------------------
  bool begin(DeviceIdentity *id = nullptr, DeviceConfig *cfg = nullptr) {
    Serial.println(F("[BLE] Dang khoi tao Bluetooth..."));

    _id = id;
    _cfg = cfg;

    // Ten quang ba lay tu ma may de moi thiet bi mot ten khac nhau.
    const char *tenQuangBa = (_id != nullptr && _id->isReady())
                                 ? _id->id()
                                 : BLE_DEVICE_NAME_FALLBACK;

    BLEDevice::init(tenQuangBa);

    // ---- Nang cong suat phat ----
    // Mac dinh ESP32-S3 phat o muc rat thap; voi thiet bi canh bao thi tam
    // song quan trong hon tiet kiem dien. Phai goi SAU BLEDevice::init().
    esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_ADV, BLE_TX_POWER_LEVEL);
    esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_DEFAULT, BLE_TX_POWER_LEVEL);
    esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_CONN_HDL0, BLE_TX_POWER_LEVEL);

    _server = BLEDevice::createServer();
    if (_server == nullptr) {
      Serial.println(F("[BLE] [LOI] Khong tao duoc BLE server."));
      return false;
    }
    _tracker.daXacThuc = &_daXacThuc;
    _server->setCallbacks(&_tracker);

    BLEService *service = _server->createService(BLE_SERVICE_UUID);
    if (service == nullptr) {
      Serial.println(F("[BLE] [LOI] Khong tao duoc BLE service."));
      return false;
    }

    // ---- Dac tinh ALERT: day ban tin canh bao sang dien thoai ----
    _alertChar = service->createCharacteristic(
        BLE_CHAR_ALERT_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
    // Descriptor 0x2902 la bat buoc thi app moi dang ky nhan NOTIFY duoc.
    _alertChar->addDescriptor(new BLE2902());
    _alertChar->setValue("READY");

    // ---- Dac tinh STATUS: nhip tim bao con song ----
    _statusChar = service->createCharacteristic(
        BLE_CHAR_STATUS_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
    _statusChar->addDescriptor(new BLE2902());
    _statusChar->setValue("BOOT");

    // ---- Dac tinh AUTH: chung minh day la thiet bi that ----
    // WRITE de app gui chuoi ngau nhien, READ de app doc loi giai ve.
    if (_id != nullptr) {
      _authChar = service->createCharacteristic(
          BLE_CHAR_AUTH_UUID,
          BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE);
      _authCb = new BleAuthCallbacks(_id, &_daXacThuc);
      _authChar->setCallbacks(_authCb);
      _authChar->setValue("READY");
    }

    // ---- Dac tinh CONFIG: app ghi WiFi/Telegram xuong ----
    if (_cfg != nullptr) {
      _configChar = service->createCharacteristic(
          BLE_CHAR_CONFIG_UUID,
          BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE);
      _configCb = new BleConfigCallbacks(_cfg, &_daXacThuc);
      _configChar->setCallbacks(_configCb);
      _configChar->setValue("READY");
    }

    // ---- Dac tinh INFO: thiet bi tu mo ta minh cho app ----
    _infoChar = service->createCharacteristic(
        BLE_CHAR_INFO_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
    _infoChar->addDescriptor(new BLE2902());
    _infoChar->setValue("");

    service->start();

    // ---- Soan goi tin quang ba ----
    // Goi quang ba chi co 31 byte. Rieng UUID 128-bit da chiem 18 byte, nen
    // ten may va ma nhan dang phai day sang goi tra loi quet (scan response),
    // neu khong thu vien se lang le cat bot va app khong thay gi ca.
    BLEAdvertising *adv = BLEDevice::getAdvertising();

    BLEAdvertisementData duLieuQuangBa;
    duLieuQuangBa.setFlags(0x06); // BR/EDR khong ho tro + che do tim thay chung
    duLieuQuangBa.setCompleteServices(BLEUUID(BLE_SERVICE_UUID));

    BLEAdvertisementData duLieuTraLoi;
    duLieuTraLoi.setName(tenQuangBa);
    if (_id != nullptr && _id->isReady()) {
      // 2 byte ma nha san xuat (little endian) + 1 byte loai may + 6 byte MAC.
      // App doc duoc ma may va loai may ngay luc quet, khong can ket noi.
      uint8_t nhanDang[9];
      nhanDang[0] = static_cast<uint8_t>(BLE_MANUFACTURER_ID & 0xFF);
      nhanDang[1] = static_cast<uint8_t>((BLE_MANUFACTURER_ID >> 8) & 0xFF);
      nhanDang[2] = _id->loai();
      memcpy(nhanDang + 3, _id->macBytes(), 6);
      duLieuTraLoi.setManufacturerData(
          std::string(reinterpret_cast<char *>(nhanDang), sizeof(nhanDang)));
    }

    adv->setAdvertisementData(duLieuQuangBa);
    adv->setScanResponseData(duLieuTraLoi);
    adv->setScanResponse(true);
    // Hai gia tri duoi giup dien thoai iPhone tim thay thiet bi on dinh hon.
    adv->setMinPreferred(0x06);
    adv->setMinPreferred(0x12);

    // ---- Gian nhip quang ba ----
    // Mac dinh thu vien phat lai moi 20-40ms, lang phi vi nguoi dung chi mo
    // app tim thiet bi vai lan. Don vi 0.625ms: 400 = 250ms, 800 = 500ms.
    //
    // KHONG dat cham hon nua: mot so dien thoai Android bo qua thiet bi
    // quang ba thua 1 giay khi dang quet o che do tiet kiem pin.
    adv->setMinInterval(400);
    adv->setMaxInterval(800);

    // CO Y KHONG ha cong suat phat: tiet kiem duoc rat it dong, doi lai mat
    // tam xa cua duong canh bao duy nhat khong phu thuoc mang.
    BLEDevice::startAdvertising();

    _started = true;
    _lastHeartbeat = millis();

    Serial.print(F("[BLE] [OK] Dang phat quang ba voi ten '"));
    Serial.print(tenQuangBa);
    Serial.println(F("'. Mo app tren dien thoai de ghep."));
    return true;
  }

  // ------------------------------------------------------------------------
  // Dat dong mo ta thiet bi (dac tinh INFO) va bao cho app biet neu dang noi.
  //
  // Van ghi gia tri ke ca khi chua co dien thoai nao ket noi: luc app noi vao
  // no doc (READ) la thay ngay, khong phai cho lan cap nhat sau.
  // ------------------------------------------------------------------------
  void datThongTin(const String &dong) {
    if (!_started || _infoChar == nullptr) {
      return;
    }
    if (dong == _thongTinCu) {
      return; // khong co gi moi, khoi lam phien app
    }
    _thongTinCu = dong;
    _infoChar->setValue(dong.c_str());
    if (_tracker.connected) {
      _infoChar->notify();
    }
    Serial.print(F("[BLE] [INFO] "));
    Serial.println(dong);
  }

  // ------------------------------------------------------------------------
  // Gui ban tin CANH BAO NGA sang dien thoai.
  //
  // Rat nhanh (vai chuc mili giay) nen duoc goi NGAY khi phat hien nga,
  // truoc ca Telegram - do la uu the lon nhat cua lop nay so voi WiFi.
  //
  // Gui lap lai vai lan cach nhau 400ms (do loop() lo, KHONG chan): goi tin
  // BLE khong co co che bao nhan, song yeu la roi mat. Nga la tinh huong khan
  // cap nen tha gui thua con hon de mat.
  // ------------------------------------------------------------------------
  bool notifyFall(float confidence) {
    if (!_started || _alertChar == nullptr) {
      return false;
    }

    // Dinh dang FALL|<do_tin_cay*100, 1 so le>|<uptime_ms>, dung bo dem co dinh.
    snprintf(_alertPayload, sizeof(_alertPayload), "FALL|%.1f|%lu",
             static_cast<double>(confidence * 100.0f),
             static_cast<unsigned long>(millis()));
    _lapConLai = 0;

    // Luon ghi gia tri vao dac tinh: neu dien thoai ket noi muon mot chut,
    // app doc (READ) se thay duoc ban tin canh bao vua roi.
    _alertChar->setValue(reinterpret_cast<uint8_t *>(_alertPayload),
                         strlen(_alertPayload));

    if (!_tracker.connected) {
      Serial.println(F("[BLE] [CANH BAO] Chua co dien thoai nao ket noi -"));
      Serial.println(F("[BLE]            khong day duoc ban tin canh bao."));
      return false;
    }

    // Lan dau gui ngay (0 ms); cac lan lap con lai do loop() gui khong chan.
    _alertChar->notify();
    _lapConLai = BLE_ALERT_REPEAT_COUNT - 1;
    _lanLapCuoi = millis();

    Serial.print(F("[BLE] [OK] Da day ban tin canh bao sang dien thoai: "));
    Serial.println(_alertPayload);
    return true;
  }

  // ------------------------------------------------------------------------
  // Goi trong loop(). Lam 2 viec nhe:
  //   - Phat lai quang ba sau khi dien thoai ngat ket noi.
  //   - Gui nhip tim moi 10 giay de app biet thiet bi con song.
  // Ham nay khong bao gio chan luong chinh qua 1ms.
  // ------------------------------------------------------------------------
  void loop(bool wifiConnected) {
    if (!_started) {
      return;
    }

    // Dien thoai vua ngat -> phat quang ba lai de no tu ket noi lai duoc.
    if (_tracker.justDisconnected) {
      _tracker.justDisconnected = false;
      delay(100); // cho ngan xep BLE don dep xong
      BLEDevice::startAdvertising();
      Serial.println(F("[BLE] Phat quang ba tro lai, cho dien thoai ket noi."));
    }

    // Gui lap ban tin canh bao khong chan; phai chay TRUOC early-return nhip tim.
    if (_lapConLai > 0) {
      if (!_tracker.connected) {
        _lapConLai = 0; // mat ket noi: bo cac lan lap, giu gia tri cho READ
      } else if (millis() - _lanLapCuoi >= BLE_ALERT_REPEAT_GAP_MS) {
        _alertChar->notify();
        _lapConLai--;
        _lanLapCuoi = millis();
      }
    }

    unsigned long now = millis();
    if (now - _lastHeartbeat < BLE_HEARTBEAT_INTERVAL_MS) {
      return;
    }
    _lastHeartbeat = now;

    if (_tracker.connected && _statusChar != nullptr) {
      String beat = F("ALIVE|");
      beat += String(now);
      beat += F("|");
      beat += wifiConnected ? F("1") : F("0");
      _statusChar->setValue(beat.c_str());
      _statusChar->notify();
    }
  }

private:
  BLEServer *_server;
  BLECharacteristic *_alertChar;
  BLECharacteristic *_statusChar;
  BLECharacteristic *_authChar;
  BLECharacteristic *_configChar;
  BLECharacteristic *_infoChar;

  /// Ban ghi cuoi cua dac tinh INFO, de khong gui lai y het gia tri cu.
  String _thongTinCu;

  // Cap phat bang new va co y KHONG giai phong: thu vien BLE giu con tro nay
  // suot doi chuong trinh, xoa di la treo ngay lan ghi tiep theo.
  BleAuthCallbacks *_authCb;
  BleConfigCallbacks *_configCb;

  DeviceIdentity *_id;
  DeviceConfig *_cfg;

  /// Phien BLE hien tai da xac thuc chua. Bi xoa moi lan ket noi hoac dut.
  volatile bool _daXacThuc;

  BleConnectionTracker _tracker;
  unsigned long _lastHeartbeat;
  bool _started;

  // Ban tin canh bao va trang thai gui lap khong chan.
  char _alertPayload[48];
  int _lapConLai;
  unsigned long _lanLapCuoi;
};

#endif // BLE_ALERT_H
