#pragma once
#include <stddef.h>
#include <stdint.h>
#include <string.h>
struct FakeWire {
  uint8_t reg[256] = {}, tx[2] = {}, pointer = 0;
  size_t txCount = 0, remaining = 0;
  int failWrite = -1, corruptReg = -1;
  bool shortRead = false, nack = false, repeatedStart = false, beginOk = true;
  uint8_t lastAddress = 0;
  int beginCount = 0, endCount = 0;
  uint16_t timeout = 0;
  bool begin(int, int, uint32_t) { ++beginCount; return beginOk; }
  void end() { ++endCount; }
  void setTimeOut(uint16_t ms) { timeout = ms; }
  void beginTransmission(uint8_t addr) { lastAddress = addr; txCount = 0; }
  void write(uint8_t b) { if (txCount < 2) tx[txCount++] = b; }
  uint8_t endTransmission(bool stop) {
    if (nack) return 2;
    if (txCount == 2) {
      if (tx[0] == failWrite) return 3;
      reg[tx[0]] = tx[1];
    } else if (txCount == 1) { pointer = tx[0]; repeatedStart = !stop; }
    return 0;
  }
  size_t requestFrom(uint8_t, size_t n, bool) { remaining = shortRead ? n - 1 : n; return remaining; }
  int available() { return static_cast<int>(remaining); }
  int read() {
    if (!remaining) return -1;
    --remaining;
    int value = reg[pointer];
    if (pointer == corruptReg) value ^= 1;
    ++pointer;
    return value;
  }
};
inline FakeWire Wire;
