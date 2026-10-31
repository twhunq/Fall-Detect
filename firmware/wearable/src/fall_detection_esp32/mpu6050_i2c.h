#pragma once
#include <Arduino.h>
#include <Wire.h>
#include "board_config.h"

struct MPU6050Data { float ax_g, ay_g, az_g, gx_dps, gy_dps, gz_dps; };

// MPU6050 only: other MPU/ICM identities require their own register maps.
// Reset and stabilization are asynchronous so the touch/alarm loop keeps running.
class MPU6050_I2C {
 public:
  enum class State { Offline, ResetWait, ClockWait, Settle, Ready, Failed };
  enum class ReadResult { NoData, Ok, Error };
  explicit MPU6050_I2C(uint8_t address = 0x68) : address_(address) {}
  State state() const { return state_; }
  bool ready() const { return state_ == State::Ready; }
  bool begin() {
    state_ = State::Failed;
    if (busStarted_) { Wire.end(); busStarted_ = false; }
    if (!releaseBus()) return false;
    if (!Wire.begin(Board::SDA, Board::SCL, Board::I2C_HZ)) return false;
    busStarted_ = true;
    Wire.setTimeOut(Board::I2C_TIMEOUT_MS);
    uint8_t who = 0;
    // WHO_AM_I stays 0x68 even when AD0 selects address 0x69.
    if (!readBytes(0x75, &who, 1) || who != 0x68 || !writeRegister(0x6B, 0x80))
      return false;
    state_ = State::ResetWait;
    changed_ = millis();
    return true;
  }
  // Puts the chip to sleep (SLEEP bit) and frees the bus before deep sleep; errors ignored.
  void sleep() {
    if (busStarted_) { writeRegister(0x6B, 0x40); Wire.end(); busStarted_ = false; }
    state_ = State::Offline;
  }
  void service(uint32_t now) {
    if (state_ == State::ResetWait && uint32_t(now - changed_) >= 100) {
      if (!writeRegister(0x6B, 0x01)) { state_ = State::Failed; return; }
      state_ = State::ClockWait;
      changed_ = millis();
    } else if (state_ == State::ClockWait && uint32_t(now - changed_) >= 30) {
      // PLL X gyro, all axes, DLPF ~21 Hz, 1 kHz / (19+1) = 50 Hz.
      // +/-4g and +/-500 dps retain the ranges/units used by the model.
      // INT active HIGH and latched, cleared by reading INT_STATUS only.
      const uint8_t registers[][2] = {
        {0x6B, 0x01}, {0x6C, 0x00}, {0x1A, 0x04}, {0x19, 19},
        {0x1B, 0x08}, {0x1C, 0x08}, {0x23, 0x00}, {0x6A, 0x00},
        {0x37, 0x20}, {0x38, 0x01}
      };
      for (const auto &r : registers) {
        uint8_t actual = 0;
        if (!writeRegister(r[0], r[1]) || !readBytes(r[0], &actual, 1) || actual != r[1]) {
          state_ = State::Failed;
          return;
        }
      }
      state_ = State::Settle;
      changed_ = millis();
    } else if (state_ == State::Settle && uint32_t(now - changed_) >= 100) {
      uint8_t discard[15];
      if (!readBytes(0x3A, discard, sizeof(discard))) { state_ = State::Failed; return; }
      state_ = State::Ready;
    }
  }
  ReadResult readData(MPU6050Data &out) {
    if (!ready()) return ReadResult::Error;
    if (digitalRead(Board::MPU_INT) == LOW) return ReadResult::NoData;
    uint8_t b[15]; // INT_STATUS + accel + temperature + gyro in one burst
    if (!readBytes(0x3A, b, sizeof(b))) return ReadResult::Error;
    if (!(b[0] & 0x01)) return ReadResult::NoData;
    out.ax_g = signed16(b + 1) / 8192.0f;
    out.ay_g = signed16(b + 3) / 8192.0f;
    out.az_g = signed16(b + 5) / 8192.0f;
    out.gx_dps = signed16(b + 9) / 65.5f;
    out.gy_dps = signed16(b + 11) / 65.5f;
    out.gz_dps = signed16(b + 13) / 65.5f;
    return ReadResult::Ok;
  }
 private:
  uint8_t address_;
  bool busStarted_ = false;
  State state_ = State::Offline;
  uint32_t changed_ = 0;
  static int16_t signed16(const uint8_t *b) {
    return static_cast<int16_t>((uint16_t(b[0]) << 8) | b[1]);
  }
  static bool releaseBus() {
    // Open drain only, up to 9 clock pulses and STOP; never force HIGH.
    digitalWrite(Board::SDA, HIGH); digitalWrite(Board::SCL, HIGH);
    pinMode(Board::SDA, OUTPUT_OPEN_DRAIN);
    pinMode(Board::SCL, OUTPUT_OPEN_DRAIN);
    delayMicroseconds(5);
    if (!digitalRead(Board::SCL)) return false;
    for (int i = 0; i < 9 && !digitalRead(Board::SDA); ++i) {
      digitalWrite(Board::SCL, LOW); delayMicroseconds(5);
      digitalWrite(Board::SCL, HIGH); delayMicroseconds(5);
      if (!digitalRead(Board::SCL)) return false;
    }
    digitalWrite(Board::SCL, LOW);
    digitalWrite(Board::SDA, LOW); delayMicroseconds(5);
    digitalWrite(Board::SCL, HIGH); delayMicroseconds(5);
    digitalWrite(Board::SDA, HIGH); delayMicroseconds(5);
    return digitalRead(Board::SDA) && digitalRead(Board::SCL);
  }
  bool writeRegister(uint8_t reg, uint8_t value) {
    Wire.beginTransmission(address_);
    Wire.write(reg); Wire.write(value);
    return Wire.endTransmission(true) == 0;
  }
  bool readBytes(uint8_t reg, uint8_t *buf, size_t count) {
    Wire.beginTransmission(address_);
    Wire.write(reg);
    if (Wire.endTransmission(false) != 0) return false;
    if (Wire.requestFrom(address_, count, true) != count) {
      while (Wire.available()) Wire.read();
      return false;
    }
    for (size_t i = 0; i < count; ++i) {
      int value = Wire.read();
      if (value < 0) return false;
      buf[i] = static_cast<uint8_t>(value);
    }
    return true;
  }
};
