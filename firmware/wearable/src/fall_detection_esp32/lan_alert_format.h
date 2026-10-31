#pragma once
// Layer 1 emergency alert: a tiny UDP text packet sent on the LAN at once,
// before any TLS. Pure functions/classes (no Arduino), tested on the host.
//   BAONGA|1|<seq>|<device_id>|<KIND>|<metric>|<ip>
// metric: impact in g (Fall) or minutes still (Inactive/Resumed), 2 decimals.
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

enum class LanAlertKind : uint8_t { Fall, Inactive, Resumed };

constexpr uint16_t LAN_ALERT_PORT = 4210;

inline const char *lanAlertKindName(LanAlertKind k) {
  switch (k) {
    case LanAlertKind::Fall: return "FALL";
    case LanAlertKind::Inactive: return "INACTIVE";
    case LanAlertKind::Resumed: return "RESUMED";
  }
  return "FALL";
}

// ipv4: byte 0 (lowest) is the first octet (lwIP / IPAddress order).
// False (out stays a valid C string) if it does not fit or deviceId is bad.
inline bool formatLanAlert(char *out, size_t cap, uint32_t seq, const char *deviceId, LanAlertKind kind,
                           int32_t metricX100, uint32_t ipv4) {
  if (!out || cap == 0) return false;
  out[0] = '\0';
  if (!deviceId || !*deviceId) return false;
  for (const char *p = deviceId; *p; ++p)
    if (*p == '|' || *p == '\r' || *p == '\n') return false;
  const bool neg = metricX100 < 0;
  const uint32_t mag = neg ? uint32_t(0) - uint32_t(metricX100) : uint32_t(metricX100);
  const int n = snprintf(out, cap, "BAONGA|1|%lu|%s|%s|%s%lu.%02lu|%u.%u.%u.%u", (unsigned long)seq, deviceId,
                         lanAlertKindName(kind), neg ? "-" : "", (unsigned long)(mag / 100),
                         (unsigned long)(mag % 100), unsigned(ipv4 & 0xFF), unsigned((ipv4 >> 8) & 0xFF),
                         unsigned((ipv4 >> 16) & 0xFF), unsigned((ipv4 >> 24) & 0xFF));
  if (n < 0 || size_t(n) >= cap) {
    out[0] = '\0';
    return false;
  }
  return true;
}

// Non-blocking repeat schedule: COUNT sends, GAP_MS apart, first one at once.
class LanBurst {
 public:
  static constexpr uint8_t COUNT = 3;
  static constexpr uint32_t GAP_MS = 20;
  void start(uint32_t now) { left_ = COUNT; nextAt_ = now; }
  bool active() const { return left_ > 0; }
  bool due(uint32_t now) {
    if (!left_ || int32_t(now - nextAt_) < 0) return false;
    --left_;
    nextAt_ = now + GAP_MS;
    return true;
  }
 private:
  uint8_t left_ = 0;
  uint32_t nextAt_ = 0;
};

// Most recent web clients (phones/PCs on the LAN), who also get a unicast copy.
class RecentClients {
 public:
  static constexpr int MAX = 4;
  void note(uint32_t ip) {
    if (ip == 0 || ip == 0xFFFFFFFFu) return;
    int at = n_ < MAX ? n_ : MAX - 1; // not found: replace the oldest / append
    for (int i = 0; i < n_; ++i)
      if (ip_[i] == ip) { at = i; break; }
    if (at == n_) ++n_; // appended slot (list was not full)
    for (int i = at; i > 0; --i) ip_[i] = ip_[i - 1];
    ip_[0] = ip;
  }
  int copy(uint32_t out[MAX]) const {
    for (int i = 0; i < n_; ++i) out[i] = ip_[i];
    return n_;
  }
 private:
  uint32_t ip_[MAX] = {};
  int n_ = 0;
};
