#pragma once
#include <stdint.h>
#include <stddef.h>
constexpr int LOW = 0, HIGH = 1, OUTPUT_OPEN_DRAIN = 3;
inline uint32_t fakeMs = 0;
inline bool stuckSda = false, stuckScl = false, dataReady = true;
inline uint32_t millis() { return fakeMs; }
inline void delayMicroseconds(unsigned) {}
inline void digitalWrite(int, int) {}
inline void pinMode(int, int) {}
inline int digitalRead(int pin) {
  if (pin == 8) return !stuckSda;
  if (pin == 9) return !stuckScl;
  if (pin == 7) return dataReady;
  return HIGH;
}
