#pragma once
#include <math.h>
#include <stdint.h>
#include "imu_filter.h"

// Wearer calibration from raw sensor samples: device worn, wearer upright and
// still. Measures gyro zero-rate bias, gravity magnitude and gravity direction.
// Any movement restarts the 3 s capture until CAL_TIMEOUT_MS expires.
class Calibrator {
 public:
  enum class State { Idle, Settling, Collecting, Done, Failed };
  State state() const { return state_; }
  bool busy() const { return state_ == State::Settling || state_ == State::Collecting; }
  const ImuCalibration &result() const { return result_; }

  void start(uint32_t now) { state_ = State::Settling; started_ = phase_ = now; clearSums(); }
  void cancel() { if (busy()) state_ = State::Failed; }

  State update(const float raw[Board::CHANNELS], uint32_t now) {
    if (!busy()) return state_;
    if (uint32_t(now - started_) >= Detect::CAL_TIMEOUT_MS) { state_ = State::Failed; return state_; }
    if (state_ == State::Settling) {
      if (uint32_t(now - phase_) < Detect::CAL_SETTLE_MS) return state_;
      state_ = State::Collecting;
    }
    for (int c = 0; c < Board::CHANNELS; ++c) {
      sum_[c] += raw[c];
      sumSq_[c] += double(raw[c]) * raw[c];
    }
    if (++count_ < Detect::CAL_SAMPLES) return state_;
    if (!evaluate()) clearSums(); // Moved: capture again.
    return state_;
  }

 private:
  State state_ = State::Idle;
  uint32_t started_ = 0, phase_ = 0;
  double sum_[Board::CHANNELS] = {}, sumSq_[Board::CHANNELS] = {};
  int count_ = 0;
  ImuCalibration result_;

  void clearSums() {
    count_ = 0;
    for (int c = 0; c < Board::CHANNELS; ++c) sum_[c] = sumSq_[c] = 0;
  }
  bool evaluate() {
    float mean[Board::CHANNELS];
    for (int c = 0; c < Board::CHANNELS; ++c) {
      mean[c] = float(sum_[c] / count_);
      double var = sumSq_[c] / count_ - double(mean[c]) * mean[c];
      float std = var > 0 ? float(sqrt(var)) : 0.0f;
      float limit = c < 3 ? Detect::CAL_MAX_ACC_STD_G : Detect::CAL_MAX_GYRO_STD_DPS;
      if (!isfinite(std) || std > limit) return false;
      if (c >= 3 && fabsf(mean[c]) > Detect::CAL_MAX_GYRO_BIAS_DPS) return false;
    }
    const float g = sqrtf(mean[0] * mean[0] + mean[1] * mean[1] + mean[2] * mean[2]);
    if (!(g >= Detect::CAL_MIN_G && g <= Detect::CAL_MAX_G)) return false;
    ImuCalibration cal;
    const float u[3] = {mean[0] / g, mean[1] / g, mean[2] / g};
    alignToZ(u, cal.rot);
    cal.accelScale = 1.0f / g;
    for (int i = 0; i < 3; ++i) cal.gyroBias[i] = mean[i + 3];
    cal.valid = cal.finite();
    if (!cal.valid) return false;
    result_ = cal;
    state_ = State::Done;
    return true;
  }
};
