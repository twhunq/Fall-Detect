/* ==========================================================================
 * main.cpp
 * --------------------------------------------------------------------------
 * ESP32-S3 lam CAU NOI cho camera K230.
 *
 * K230 lo phan nhin: chay YOLOv5n, bo phieu M-trong-N, xac nhan theo thoi
 * luong (xem k230/falldown_detect.py). Khi chac chan co nguoi nga, no ban mot
 * dong chu qua UART sang day. Bo mach nay lo phan con lai: quang ba BLE cho
 * app ghep, nhan cau hinh, va bao ve nguoi than.
 *
 * --------------------------------------------------------------------------
 * VI SAO TACH LAM HAI CON CHIP
 *
 * K230 manh ve xu ly anh nhung phan mem cua no la MicroPython tren CanMV, ho
 * tro BLE han che va khong dung chung duoc bo ma dinh danh/xac thuc ma ca he
 * thong dang dung. Trong khi do vong deo da co san toan bo phan do tren
 * ESP32-S3. Ghep them mot con ESP32-S3 vao camera thi camera ke thua nguyen
 * bo: cung cach ghep may, cung ma QR, cung duong cau hinh, cung giao thuc BLE.
 * App chi phai biet MOT loai thiet bi thay vi hai.
 *
 * --------------------------------------------------------------------------
 * VI SAO VIDEO KHONG DI QUA DAY
 *
 * UART 115200 baud la khoang 14KB/giay. Mot anh JPEG 640x480 nang chung 30KB
 * -> hon 2 giay cho MOT khung hinh. Khong the thanh video.
 *
 * Nen chia lam hai duong:
 *   - Duong SU KIEN (day): UART -> ESP32 -> BLE/mang. Nhe, tin cay, la thu
 *     quyet dinh nguoi than co duoc bao hay khong.
 *   - Duong HINH ANH: K230 tu dung WiFi cua no, phat MJPEG cho app xem trong
 *     mang nha va tu day anh bang chung len server.
 *
 * THU TU BAO KHI CO NGA (nhanh -> cham, khong cai nao chan cai truoc):
 *   BLE notify (0ms, lap 400ms khong chan) -> UDP broadcast LAN cong 4210
 *   (lan_alert_udp.h, gui 3 lan cach 20ms) -> Relay -> Telegram.
 *
 * UART de o 921600 baud vi phai bao cang som cang tot - moi mili giay deu
 * dang gia khi co nguoi nga.
 *
 * --------------------------------------------------------------------------
 * DAU NOI DAY
 *
 *   K230 UART TX  ->  ESP32-S3 GPIO 18 (RX)
 *   K230 UART RX  <-  ESP32-S3 GPIO 17 (TX)
 *   GND           ->  GND        <- BAT BUOC, thieu day nay thi du lieu ra rac
 *
 * Ca hai bo deu dung muc logic 3.3V nen noi thang, khong can mach chuyen muc.
 *
 * --------------------------------------------------------------------------
 * GIAO THUC UART (chu thuong, ket thuc bang xuong dong)
 *
 *   K230 -> ESP32:
 *     FALL,<track_id>,<do_tin_cay 0..1>,<moc_thoi_gian_ms>
 *     IP,<dia_chi_ip>,<cong>,<duong_dan>      vi du: IP,192.168.1.50,81,/stream
 *     HB,<fps>,<so_nguoi_trong_khung>         nhip tim moi 5 giay
     LOG,<noi_dung>                          log cua K230, in ra Serial voi
                                             tien to [K230] (K230 chay tu the
                                             nho nen day la kenh log duy nhat)
 *
 *   ESP32 -> K230:
 *     CFG,<ma_nha>,<ma_may>,<dia_chi_relay>   K230 can biet day anh len dau
 *     SNAP,<ma_su_kien>,<phieu_tai_anh>       bao K230 day anh bang chung len
 *
 * PHIEU TAI ANH giai quyet mot chuyen te nhi: khoa rieng cua thiet bi nam
 * tren con ESP32 nay, khong nam tren K230. Co the truyen khoa sang K230 qua
 * day UART, nhung nhu vay la nhan ban mot bi mat ra them mot cho nua ma chang
 * duoc loi gi. Thay vao do ESP32 ky request bao nga (no co khoa), nhan ve mot
 * phieu dung mot lan song 5 phut, roi dua phieu do cho K230.
 * ========================================================================== */

#include <Arduino.h>

// Dat ten rieng TRUOC khi include telegram_alert.h - tin nhan gui di se ghi
// dung day la camera chu khong phai vong deo.
#define TELEGRAM_DEVICE_NAME "Camera giám sát"

#include "ble_alert.h"
#include "device_config.h"
#include "device_identity.h"
#include "lan_alert_udp.h"
#include "relay_client.h"
#include "telegram_alert.h"

// --------------------------------------------------------------------------
// So do chan
// --------------------------------------------------------------------------
// Tranh cac chan strapping (0, 3, 45, 46), USB native (19, 20), UART0
// (43, 44) va nhom 26-37 da bi SPI flash + Octal PSRAM chiem tren N16R8.
#define PIN_UART_RX 18 // noi toi chan TX cua K230
#define PIN_UART_TX 17 // noi toi chan RX cua K230
#define PIN_LED 5      // den bao trang thai, noi tiep dien tro 220 ohm

#define UART_BAUD 921600
#define UART_PORT 1 // UART0 dang dung cho Serial Monitor

// --------------------------------------------------------------------------
// Cac nguong thoi gian
// --------------------------------------------------------------------------

// Khong nhan duoc nhip tim cua K230 qua lau thi coi nhu camera da chet. Bao
// len app chu khong im lang: nguoi nha dang tin la co camera trong khi thuc
// te khong ai nhin ca - do la kieu hong nguy hiem nhat cua he canh bao.
#define K230_TIMEOUT_MS 30000UL

// Hai dong FALL cach nhau qua gan la cung mot cu nga. K230 da co cooldown 15
// giay roi, day chi la lop chan thu hai phong khi no bi sua cau hinh.
#define FALL_DEBOUNCE_MS 15000UL

// Dinh ky gui lai cau hinh sang K230, phong khi K230 khoi dong lai giua chung
// va mat het thong tin trong RAM.
#define CFG_RESEND_MS 60000UL

// Dai toi da mot dong UART. Dai hon la du lieu hong, vut di chu khong doc.
#define UART_LINE_MAX 200

// ==========================================================================
// Bo mach nay KHONG co cam bien nao: viec phat hien nga do K230 lo tron ven.
// ==========================================================================
TelegramAlert telegram;
BleAlert ble;
DeviceIdentity danhTinh;
DeviceConfig cauHinh;
RelayClient relay;
LanAlertUdp lanUdp;

HardwareSerial K230(UART_PORT);

static char g_dong[UART_LINE_MAX + 1];
static int g_doDaiDong = 0;

static unsigned long g_lanCuoiNhanHB = 0;
static unsigned long g_lanCuoiBaoNga = 0;
static unsigned long g_lanCuoiGuiCfg = 0;
static bool g_k230Song = false;

static String g_cfgDaGui;
static String g_diaChiXemHinh; // "CAM|ip|cong|duong_dan"

// ==========================================================================
// Gui cau hinh sang K230
//
// K230 can dia chi server de biet day anh len dau. Ma nha va ma may gui kem
// de tien tra cuu khi doc log, con viec gan anh vao dung su kien thi da co
// PHIEU tai anh lo - xem ham xuLyDong().
//
// Gui lai dinh ky vi K230 co the khoi dong lai giua chung va mat het thong
// tin trong RAM, trong khi bo mach nay van chay lien tuc.
// ==========================================================================
void guiCauHinhSangK230(bool epGui) {
  String dong = F("CFG,");
  dong += cauHinh.maNha();
  dong += ',';
  dong += danhTinh.id();
  dong += ',';
  dong += cauHinh.relayUrl();

  const unsigned long now = millis();
  const bool daDoi = (dong != g_cfgDaGui);
  const bool denHen = (now - g_lanCuoiGuiCfg >= CFG_RESEND_MS);

  if (!epGui && !daDoi && !denHen) {
    return;
  }

  K230.print(dong);
  K230.print('\n');
  g_cfgDaGui = dong;
  g_lanCuoiGuiCfg = now;

  if (daDoi) {
    Serial.print(F("[CAU NOI] Da gui cau hinh sang K230: "));
    Serial.println(dong);
  }
}

// ==========================================================================
// Cap nhat dong mo ta thiet bi cho app doc
//
// App can dia chi xem hinh de mo luong video, va can biet camera con song hay
// khong. Gop ca hai vao mot dong de app chi phai doc mot cho.
//
// Dinh dang:  CAM|<ip>|<cong>|<duong_dan>|<0 mat / 1 song>
// ==========================================================================
void capNhatThongTinChoApp() {
  String dong = g_diaChiXemHinh.isEmpty() ? String(F("CAM|||"))
                                          : g_diaChiXemHinh;
  dong += '|';
  dong += g_k230Song ? '1' : '0';
  ble.datThongTin(dong);
}

// ==========================================================================
// Xu ly mot dong nhan duoc tu K230
// ==========================================================================
void xuLyDong(const char *dong) {
  // ---- Canh bao nga ----
  if (strncmp(dong, "FALL,", 5) == 0) {
    // FALL,<track_id>,<do_tin_cay>,<moc_thoi_gian>
    float doTinCay = 0.0f;
    int trackId = 0;
    if (sscanf(dong + 5, "%d,%f", &trackId, &doTinCay) < 2) {
      Serial.println(F("[CAU NOI] [LOI] Dong FALL sai dinh dang, bo qua."));
      return;
    }

    const unsigned long now = millis();
    if (g_lanCuoiBaoNga != 0 && now - g_lanCuoiBaoNga < FALL_DEBOUNCE_MS) {
      Serial.println(F("[CAU NOI] Bo qua bao trung trong cua so chong dop."));
      return;
    }
    g_lanCuoiBaoNga = now;

    Serial.print(F("[CAU NOI] [CANH BAO] K230 bao co nguoi nga, do tin cay "));
    Serial.println(doTinCay, 2);

    digitalWrite(PIN_LED, HIGH);

    // Day BLE TRUOC: no chi ton vai chuc mili giay va khong can mang, trong
    // khi Telegram ton vai giay va co the that bai hoan toan neu mat WiFi.
    ble.notifyFall(doTinCay);

    // UDP broadcast LAN: gui ngay, truoc relay/Telegram (cac ham do chan).
    lanUdp.trigger(danhTinh.id(), doTinCay);

    // Roi moi den duong mang.
    //
    // Uu tien relay: no gop bao cao nay voi bao cao cua vong deo thanh MOT
    // tin, va no cap cho ta mot PHIEU de K230 day anh bang chung len. Nho
    // phieu do ma K230 khong phai giu khoa rieng cua thiet bi.
    bool daBao = false;
    if (relay.sanSang()) {
      const RelayKetQua kq = relay.baoNga("cam", doTinCay);
      daBao = kq.ok;
      if (kq.ok && !kq.phieuAnh.isEmpty()) {
        String lenh = F("SNAP,");
        lenh += kq.maSuKien;
        lenh += ',';
        lenh += kq.phieuAnh;
        K230.print(lenh);
        K230.print('\n');
        Serial.println(F("[CAU NOI] Da bao K230 day anh bang chung len."));
      }
    }
    if (!daBao) {
      // Relay chet hoac chua cau hinh thi goi thang Telegram - tha nhan hai
      // tin con hon khong nhan tin nao.
      telegram.sendFallAlert(doTinCay);
    }

    digitalWrite(PIN_LED, LOW);
    return;
  }

  // ---- K230 bao dia chi xem hinh ----
  if (strncmp(dong, "IP,", 3) == 0) {
    // IP,<ip>,<cong>,<duong_dan>
    char ip[24] = {0};
    int cong = 0;
    char duongDan[40] = {0};
    if (sscanf(dong + 3, "%23[^,],%d,%39s", ip, &cong, duongDan) < 3) {
      Serial.println(F("[CAU NOI] [LOI] Dong IP sai dinh dang, bo qua."));
      return;
    }

    String moi = F("CAM|");
    moi += ip;
    moi += '|';
    moi += cong;
    moi += '|';
    moi += duongDan;

    if (moi != g_diaChiXemHinh) {
      g_diaChiXemHinh = moi;
      Serial.print(F("[CAU NOI] Dia chi xem hinh: "));
      Serial.println(g_diaChiXemHinh);
      capNhatThongTinChoApp();
    }
    return;
  }

  // ---- Nhip tim ----
  if (strncmp(dong, "HB,", 3) == 0) {
    g_lanCuoiNhanHB = millis();
    if (!g_k230Song) {
      g_k230Song = true;
      Serial.println(F("[CAU NOI] K230 da song tro lai."));
      capNhatThongTinChoApp();
      // K230 vua khoi dong lai thi khong con nho cau hinh, gui lai ngay.
      guiCauHinhSangK230(true);
    }
    return;
  }

  // ---- Log cua K230 ----
  if (strncmp(dong, "LOG,", 4) == 0) {
    Serial.print(F("[K230] "));
    Serial.println(dong + 4);
    return;
  }

  Serial.print(F("[CAU NOI] Dong la, bo qua: "));
  Serial.println(dong);
}

// ==========================================================================
// Doc UART theo tung ky tu, gom thanh dong
//
// Khong dung readStringUntil(): ham do CHAN luong chinh cho toi khi du dong
// hoac het thoi gian cho. Neu K230 gui nua dong roi treo, ca bo mach nay
// dung theo - va luc do BLE cung chet, khong con duong bao nao ca.
// ==========================================================================
void docUart() {
  while (K230.available() > 0) {
    const int c = K230.read();
    if (c < 0) {
      break;
    }

    if (c == '\n' || c == '\r') {
      if (g_doDaiDong > 0) {
        g_dong[g_doDaiDong] = '\0';
        xuLyDong(g_dong);
        g_doDaiDong = 0;
      }
      continue;
    }

    if (g_doDaiDong >= UART_LINE_MAX) {
      // Dong qua dai = du lieu hong hoac mat dong bo. Vut ca dong roi cho
      // dong sau, chu khong cat bot rui may lai doc nham thanh lenh that.
      g_doDaiDong = 0;
      Serial.println(F("[CAU NOI] [LOI] Dong UART qua dai, da vut bo."));
      continue;
    }

    g_dong[g_doDaiDong++] = static_cast<char>(c);
  }
}

// ==========================================================================
void setup() {
  Serial.begin(115200);
  delay(300);

  Serial.println();
  Serial.println(F("=========================================="));
  Serial.println(F("  CAU NOI CAMERA K230  <->  ESP32-S3"));
  Serial.println(F("=========================================="));

  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, LOW);

  // Doc ma may tu efuse va nap khoa rieng. Phai chay TRUOC BLE vi ten quang
  // ba lay tu chinh ma may nay.
  danhTinh.begin();

  cauHinh.begin(WIFI_SSID, WIFI_PASSWORD, TELEGRAM_BOT_TOKEN,
                TELEGRAM_CHAT_ID);
  telegram.setConfig(&cauHinh);
  relay.begin(&danhTinh, &cauHinh);

  // Mo UART sang K230 truoc khi lam viec khac, de khong bo lo dong nao neu
  // K230 khoi dong nhanh hon bo mach nay.
  K230.begin(UART_BAUD, SERIAL_8N1, PIN_UART_RX, PIN_UART_TX);
  Serial.print(F("[CAU NOI] Da mo UART "));
  Serial.print(UART_BAUD);
  Serial.print(F(" baud (RX=GPIO"));
  Serial.print(PIN_UART_RX);
  Serial.print(F(", TX=GPIO"));
  Serial.print(PIN_UART_TX);
  Serial.println(F(")."));

  // Bat BLE TRUOC WiFi: day la duong canh bao duy nhat khong phu thuoc mang.
  ble.begin(&danhTinh, &cauHinh);
  capNhatThongTinChoApp();

  telegram.begin();

  guiCauHinhSangK230(true);

  Serial.println(F("[CAU NOI] San sang. Dang cho tin hieu tu K230..."));
}

// ==========================================================================
void loop() {
  docUart();

  // Nghe lenh nap khoa tu cong cu nap khoa qua cong USB. Khong ton gi khi
  // khong co ai gui lenh.
  danhTinh.phucVuSerial();

  ble.loop(telegram.isConnected());
  lanUdp.loop();

  // ---- Theo doi K230 con song khong ----
  const unsigned long now = millis();
  if (g_k230Song && g_lanCuoiNhanHB != 0 &&
      now - g_lanCuoiNhanHB > K230_TIMEOUT_MS) {
    g_k230Song = false;
    Serial.println(F("[CAU NOI] [CANH BAO] Mat tin hieu K230 qua 30 giay."));
    Serial.println(F("[CAU NOI]            Camera coi nhu khong con giam sat."));
    capNhatThongTinChoApp();
  }

  guiCauHinhSangK230(false);

  delay(5);
}
