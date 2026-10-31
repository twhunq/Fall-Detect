#pragma once
// Network state on the Super Mini's on-board WS2812 RGB LED (GPIO48). The red
// alarm LED on GPIO6 is separate and unchanged.
//   blue, fast blink    looking for / joining Wi-Fi, or Wi-Fi lost
//   green, slow blink   Wi-Fi joined, Internet not confirmed yet
//   green, steady       Internet reachable (cloud synced; without cloud: Wi-Fi joined)
//   purple, blink       setup hotspot open (BaoNga-Setup-...)
//   off                 Wi-Fi switched off
#include <stdint.h>

namespace StatusLed {
constexpr int PIN = 48;          // WS2812 on the ESP32-S3 Super Mini, not the PCB LED
constexpr uint8_t LEVEL = 24;    // of 255: visible, little battery

enum class Net : uint8_t { Off, Searching, NoInternet, Online, SetupAp };

struct Rgb {
  uint8_t r = 0, g = 0, b = 0;
  bool operator==(const Rgb &o) const { return r == o.r && g == o.g && b == o.b; }
  bool operator!=(const Rgb &o) const { return !(*this == o); }
};

// wifiJoined: STA connected. internetKnown: something proved Internet access
// (cloud online); cloudUsed: the cloud is configured, so it is the proof.
inline Net state(bool wifiOn, bool wifiJoined, bool apActive, bool cloudUsed, bool cloudOnline) {
  if (!wifiOn) return Net::Off;
  if (wifiJoined) return !cloudUsed || cloudOnline ? Net::Online : Net::NoInternet;
  return apActive ? Net::SetupAp : Net::Searching;
}

inline Rgb color(Net s, uint32_t nowMs) {
  Rgb c;
  switch (s) {
    case Net::Searching:
      if (nowMs % 500 < 250) c.b = LEVEL;                 // 2 Hz
      break;
    case Net::NoInternet:
      if (nowMs % 2000 < 1000) c.g = LEVEL;               // 0.5 Hz
      break;
    case Net::Online:
      c.g = LEVEL;
      break;
    case Net::SetupAp:
      if (nowMs % 1000 < 500) { c.r = LEVEL; c.b = LEVEL; } // 1 Hz
      break;
    default:
      break;
  }
  return c;
}
} // namespace StatusLed
