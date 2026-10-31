#pragma once
// Layer 1: UDP emergency burst on the LAN (broadcast + recent web clients),
// sent from the sensing loop (core 1) the moment an alert is confirmed, long
// before the TLS channels. Raw non-blocking lwIP socket: never waits, no heap.
// Packet format and repeat schedule: lan_alert_format.h.
#include <Arduino.h>
#include <WiFi.h>
#include <fcntl.h>
#include "lwip/sockets.h"
#include "lan_alert_format.h"

#ifndef CLOUD_DEVICE_ID
#define CLOUD_DEVICE_ID "baonga-01"
#endif

class LanAlertUdp {
 public:
  // Web task: remember who talked to this device (they get a unicast copy).
  void noteClient(uint32_t ip) {
    portENTER_CRITICAL(&lock_);
    clients_.note(ip);
    portEXIT_CRITICAL(&lock_);
  }

  // Loop task: new alert. Repeats of one burst share the same seq.
  void trigger(LanAlertKind kind, int32_t metricX100, uint32_t now) {
    ++seq_;
    uint32_t ip = uint32_t(WiFi.localIP());
    if (!ip) ip = uint32_t(WiFi.softAPIP());
    valid_ = formatLanAlert(packet_, sizeof(packet_), seq_, CLOUD_DEVICE_ID, kind, metricX100, ip);
    len_ = valid_ ? strlen(packet_) : 0;
    burst_.start(now);
    poll(now);
  }

  // Loop task, every iteration: cheap while idle.
  void poll(uint32_t now) {
    if (!burst_.active() || !burst_.due(now)) return;
    if (!valid_ || !networkUp() || !openSocket()) return;
    sendTo(0xFFFFFFFFu); // 255.255.255.255 (same byte order in memory as lwIP)
    uint32_t list[RecentClients::MAX];
    portENTER_CRITICAL(&lock_);
    const int n = clients_.copy(list);
    portEXIT_CRITICAL(&lock_);
    for (int i = 0; i < n; ++i) sendTo(list[i]);
  }

  uint32_t seq() const { return seq_; }

 private:
  RecentClients clients_;
  LanBurst burst_;
  char packet_[96] = "";
  size_t len_ = 0;
  bool valid_ = false;
  uint32_t seq_ = 0;
  int sock_ = -1;
  mutable portMUX_TYPE lock_ = portMUX_INITIALIZER_UNLOCKED;

  static bool networkUp() { return WiFi.status() == WL_CONNECTED || (WiFi.getMode() & WIFI_AP); }

  bool openSocket() {
    if (sock_ >= 0) return true;
    const int s = lwip_socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s < 0) return false;
    const int on = 1;
    lwip_setsockopt(s, SOL_SOCKET, SO_BROADCAST, &on, sizeof(on));
    lwip_fcntl(s, F_SETFL, lwip_fcntl(s, F_GETFL, 0) | O_NONBLOCK);
    sock_ = s;
    return true;
  }

  // ip in lwIP order (first octet = lowest byte). A failed send is not retried
  // here: the burst repeats it, and sockets stay open for the next alert.
  void sendTo(uint32_t ip) {
    struct sockaddr_in to = {};
    to.sin_family = AF_INET;
    to.sin_port = htons(LAN_ALERT_PORT);
    to.sin_addr.s_addr = ip;
    lwip_sendto(sock_, packet_, len_, MSG_DONTWAIT, reinterpret_cast<struct sockaddr *>(&to), sizeof(to));
  }
};
