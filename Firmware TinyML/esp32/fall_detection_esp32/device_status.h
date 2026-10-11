#pragma once
// Snapshot of what the device is doing, written by the sensing loop (core 1)
// and read by the local web page and the cloud sync task (core 0).
#include <Arduino.h>
#include <WiFi.h>
#include "notify_format.h"

struct DeviceStatus {
  const char *activity = nullptr; // CLASS_NAMES entry, nullptr until the first inference
  float confidence = 0;           // 0..1
  enum class Alarm : uint8_t { Off, Fall, Sos } alarm = Alarm::Off;
  bool imuOk = false, modelOk = false, calValid = false, calRunning = false, batteryLow = false;
  uint32_t batteryMv = 0, readErrors = 0;
  uint32_t stillSec = 0;             // time since the last body movement
  bool inactive = false;             // inactivity alert sent, wearer has not moved since

  // Changes worth telling a remote viewer about straight away.
  bool differsFrom(const DeviceStatus &o) const {
    return activity != o.activity || alarm != o.alarm || imuOk != o.imuOk || modelOk != o.modelOk ||
           calValid != o.calValid || calRunning != o.calRunning || batteryLow != o.batteryLow ||
           inactive != o.inactive || (o.stillSec >= 60 && stillSec < o.stillSec); // Moved after a still minute.
  }
};

class StatusBoard {
 public:
  void publish(const DeviceStatus &s) {
    portENTER_CRITICAL(&lock_);
    status_ = s;
    portEXIT_CRITICAL(&lock_);
  }
  DeviceStatus read() const {
    portENTER_CRITICAL(&lock_);
    DeviceStatus copy = status_;
    portEXIT_CRITICAL(&lock_);
    return copy;
  }
 private:
  mutable portMUX_TYPE lock_ = portMUX_INITIALIZER_UNLOCKED;
  DeviceStatus status_;
};

// JSON members shared by the local page and the cloud copy (no braces).
inline void formatStatusFields(TextOut &t, const DeviceStatus &s) {
  static const char *const alarms[] = {"off", "fall", "sos"};
  if (s.activity) t.addf("\"activity\":\"%s\",", s.activity);
  else t.add("\"activity\":null,");
  t.addf("\"confidence\":%.3f,\"alarm\":\"%s\",\"imu\":%s,\"model\":%s,\"cal\":\"%s\","
         "\"batteryMv\":%lu,\"batteryLow\":%s,\"errors\":%lu,\"rssi\":%d,\"ip\":\"%s\",\"uptime\":%lu",
         s.confidence, alarms[static_cast<int>(s.alarm)], s.imuOk ? "true" : "false",
         s.modelOk ? "true" : "false", s.calRunning ? "run" : (s.calValid ? "ok" : "none"),
         (unsigned long)s.batteryMv, s.batteryLow ? "true" : "false", (unsigned long)s.readErrors,
         static_cast<int>(WiFi.RSSI()), WiFi.localIP().toString().c_str(), (unsigned long)(millis() / 1000));
  t.addf(",\"stillSec\":%lu,\"inactive\":%s", (unsigned long)s.stillSec, s.inactive ? "true" : "false");
}
