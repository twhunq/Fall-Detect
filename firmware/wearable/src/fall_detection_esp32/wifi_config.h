#pragma once
// Wi-Fi networks the device joins, set on the local web page and kept in NVS
// (secrets.h WIFI_SSID/WIFI_PASSWORD is only the first default). Up to
// MAX networks, tried in order; the first is the most recently added.
// Validation is strict: the values are used as Wi-Fi credentials and printed
// into JSON, so only printable characters are accepted.
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct WifiNetworks {
  static constexpr int MAX = 3;
  static constexpr size_t SSID_CAP = 33, PASS_CAP = 65; // 32 bytes / 64 chars + NUL
  int count = 0;
  char ssid[MAX][SSID_CAP] = {};
  char pass[MAX][PASS_CAP] = {};

  int find(const char *name) const {
    for (int i = 0; i < count; ++i)
      if (strcmp(ssid[i], name) == 0) return i;
    return -1;
  }
};

// SSID: 1-32 bytes (UTF-8 allowed), no control characters or quotes/backslash
// (they would need escaping everywhere the name is shown).
inline bool validSsid(const char *s) {
  const size_t n = strlen(s);
  if (n == 0 || n > 32) return false;
  for (const unsigned char *p = reinterpret_cast<const unsigned char *>(s); *p; ++p)
    if (*p < 0x20 || *p == 0x7F || *p == '"' || *p == '\\') return false;
  return true;
}

// Empty (open network), a WPA passphrase of 8-63 printable ASCII characters,
// or a 64-digit hexadecimal key.
inline bool validWifiPassword(const char *s) {
  const size_t n = strlen(s);
  if (n == 0) return true;
  if (n == 64) {
    for (const char *p = s; *p; ++p)
      if (!((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'f') || (*p >= 'A' && *p <= 'F'))) return false;
    return true;
  }
  if (n < 8 || n > 63) return false;
  for (const unsigned char *p = reinterpret_cast<const unsigned char *>(s); *p; ++p)
    if (*p < 0x20 || *p > 0x7E) return false;
  return true;
}

// Adds a network at the top (highest priority). An existing SSID moves to
// the top with the new password; when the list is full the last one is
// dropped. On failure `message` says why (Vietnamese) and `list` is unchanged.
inline bool addWifiNetwork(WifiNetworks &list, const char *name, const char *password, char *message,
                           size_t cap) {
  if (!validSsid(name)) {
    snprintf(message, cap, "Tên Wi-Fi phải dài 1-32 byte, không chứa dấu \" hoặc \\.");
    return false;
  }
  if (!validWifiPassword(password)) {
    snprintf(message, cap, "Mật khẩu Wi-Fi phải dài 8-63 ký tự (hoặc để trống nếu mạng không có mật khẩu).");
    return false;
  }
  WifiNetworks next;
  snprintf(next.ssid[0], WifiNetworks::SSID_CAP, "%s", name); // Lengths checked above.
  snprintf(next.pass[0], WifiNetworks::PASS_CAP, "%s", password);
  next.count = 1;
  for (int i = 0; i < list.count && next.count < WifiNetworks::MAX; ++i) {
    if (strcmp(list.ssid[i], name) == 0) continue;
    memcpy(next.ssid[next.count], list.ssid[i], WifiNetworks::SSID_CAP);
    memcpy(next.pass[next.count], list.pass[i], WifiNetworks::PASS_CAP);
    ++next.count;
  }
  list = next;
  return true;
}

inline bool removeWifiNetwork(WifiNetworks &list, const char *name) {
  const int at = list.find(name);
  if (at < 0) return false;
  for (int i = at; i + 1 < list.count; ++i) {
    memcpy(list.ssid[i], list.ssid[i + 1], WifiNetworks::SSID_CAP);
    memcpy(list.pass[i], list.pass[i + 1], WifiNetworks::PASS_CAP);
  }
  --list.count;
  memset(list.ssid[list.count], 0, WifiNetworks::SSID_CAP);
  memset(list.pass[list.count], 0, WifiNetworks::PASS_CAP);
  return true;
}
