/* ==========================================================================
 * lan_alert_udp.h
 * --------------------------------------------------------------------------
 * Lop 1 cua duong bao nga: phat UDP broadcast trong mang LAN ngay khi co nga,
 * truoc ca relay/Telegram (von chan vai giay). May khac trong nha (app, loa
 * bao dong...) nghe cong 4210 la nhan duoc ngay, khong can Internet.
 *
 * Dinh dang goi tin (cung dinh dang voi vong deo, xem
 * firmware/wearable/src/fall_detection_esp32/lan_alert_format.h):
 *     BAONGA|1|<seq>|<ma_may>|FALL|<do_tin_cay 0.00..1.00>|<ip_camera>
 *
 * UDP khong co bao nhan nen gui 3 lan (1 ngay + 2 lap cach 20ms, cung seq).
 * Khong chan: lan lap do loop() gui.
 * ========================================================================== */

#ifndef LAN_ALERT_UDP_H
#define LAN_ALERT_UDP_H

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>

#define LAN_ALERT_PORT 4210
#define LAN_ALERT_REPEAT_COUNT 2
#define LAN_ALERT_REPEAT_GAP_MS 20UL

class LanAlertUdp {
public:
  LanAlertUdp()
      : _seq(0), _lapConLai(0), _lanGuiCuoi(0), _doDai(0), _daMoUdp(false),
        _daBaoThieuWifi(false) {
    _buf[0] = '\0';
  }

  void trigger(const char *deviceId, float conf) {
    if (WiFi.status() != WL_CONNECTED) {
      if (!_daBaoThieuWifi) {
        _daBaoThieuWifi = true;
        Serial.println(F("[UDP] Chua co WiFi, bo qua goi UDP"));
      }
      return;
    }
    _daBaoThieuWifi = false;
    if (!moUdp()) {
      return;
    }

    _seq++;

    // conf 0..1 -> phan tram le (hundredths) bang so nguyen, kep 0..100.
    int tram = static_cast<int>(conf * 100.0f + 0.5f);
    if (tram < 0) {
      tram = 0;
    }
    if (tram > 100) {
      tram = 100;
    }

    const IPAddress ip = WiFi.localIP();
    const int n = snprintf(_buf, sizeof(_buf), "BAONGA|1|%lu|%s|FALL|%d.%02d|%u.%u.%u.%u",
                           static_cast<unsigned long>(_seq),
                           (deviceId != nullptr) ? deviceId : "",
                           tram / 100, tram % 100, ip[0], ip[1], ip[2], ip[3]);
    if (n <= 0) {
      return;
    }
    _doDai = (static_cast<size_t>(n) < sizeof(_buf)) ? static_cast<size_t>(n)
                                                      : sizeof(_buf) - 1;

    guiMotGoi();
    _lapConLai = LAN_ALERT_REPEAT_COUNT;
    _lanGuiCuoi = millis();

    Serial.print(F("[UDP] Da phat bao nga LAN: "));
    Serial.println(_buf);
  }

  void loop() {
    if (_lapConLai <= 0) {
      return;
    }
    if (WiFi.status() != WL_CONNECTED) {
      _lapConLai = 0;
      return;
    }
    if (millis() - _lanGuiCuoi >= LAN_ALERT_REPEAT_GAP_MS) {
      guiMotGoi();
      _lapConLai--;
      _lanGuiCuoi = millis();
    }
  }

private:
  // Mo socket mot lan, luc da co WiFi. Cong cuc bo bat ky (0).
  bool moUdp() {
    if (!_daMoUdp) {
      _daMoUdp = (_udp.begin(0) == 1);
      if (!_daMoUdp) {
        Serial.println(F("[UDP] [LOI] Khong mo duoc socket UDP."));
      }
    }
    return _daMoUdp;
  }

  void guiMotGoi() {
    _udp.beginPacket(IPAddress(255, 255, 255, 255), LAN_ALERT_PORT);
    _udp.write(reinterpret_cast<const uint8_t *>(_buf), _doDai);
    _udp.endPacket();
  }

  WiFiUDP _udp;
  uint32_t _seq;
  int _lapConLai;
  unsigned long _lanGuiCuoi;
  char _buf[96];
  size_t _doDai;
  bool _daMoUdp;
  bool _daBaoThieuWifi;
};

#endif // LAN_ALERT_UDP_H
