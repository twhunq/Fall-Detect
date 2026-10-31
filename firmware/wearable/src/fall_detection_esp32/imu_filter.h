#pragma once
#include <math.h>
#include <stdint.h>
#include "board_config.h"
#include "detection_config.h"

// Sensor-frame -> body-frame correction. After calibration the wearer's upright
// gravity maps to +Z, matching the axis convention of the training data.
struct ImuCalibration {
  float gyroBias[3] = {0, 0, 0};
  float rot[3][3] = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}};
  float accelScale = 1.0f;
  bool valid = false;

  bool finite() const {
    if (!isfinite(accelScale) || accelScale <= 0) return false;
    for (int i = 0; i < 3; ++i) {
      if (!isfinite(gyroBias[i])) return false;
      for (int j = 0; j < 3; ++j)
        if (!isfinite(rot[i][j])) return false;
    }
    return true;
  }
};

// Rotation taking unit vector u onto +Z (Rodrigues formula).
inline void alignToZ(const float u[3], float rot[3][3]) {
  const float c = u[2];
  if (c < -0.9999f) { // Upside down: 180 degrees about X.
    const float flip[3][3] = {{1, 0, 0}, {0, -1, 0}, {0, 0, -1}};
    for (int i = 0; i < 3; ++i)
      for (int j = 0; j < 3; ++j) rot[i][j] = flip[i][j];
    return;
  }
  // v = u x z, K = [v]x, R = I + K + K^2 / (1 + c)
  const float vx = u[1], vy = -u[0];
  const float k[3][3] = {{0, 0, vy}, {0, 0, -vx}, {-vy, vx, 0}};
  const float f = 1.0f / (1.0f + c);
  for (int i = 0; i < 3; ++i)
    for (int j = 0; j < 3; ++j) {
      float k2 = 0;
      for (int m = 0; m < 3; ++m) k2 += k[i][m] * k[m][j];
      rot[i][j] = (i == j ? 1.0f : 0.0f) + k[i][j] + k2 * f;
    }
}

// How far a filtered sample is from the recent average of each channel
// (accelerometer in g, gyro in deg/s). Slow things (gravity direction,
// accelerometer offset, gyro bias of an uncalibrated device) cancel out;
// only actual movement of the wearer shows up.
class MotionLevel {
 public:
  float acc = 0, gyro = 0; // Latest deviations.
  void reset() { init_ = false; acc = gyro = 0; }
  void update(const float s[Board::CHANNELS]) {
    if (!init_) {
      for (int c = 0; c < Board::CHANNELS; ++c) avg_[c] = s[c];
      init_ = true;
    }
    float d2[2] = {0, 0};
    for (int c = 0; c < Board::CHANNELS; ++c) {
      const float d = s[c] - avg_[c];
      d2[c / 3] += d * d;
      avg_[c] += Detect::MOTION_AVG_ALPHA * d;
    }
    acc = sqrtf(d2[0]);
    gyro = sqrtf(d2[1]);
  }
 private:
  float avg_[Board::CHANNELS] = {};
  bool init_ = false;
};

// Applies calibration, removes single-sample glitches with a per-channel
// median of 3 (one 20 ms sample of delay) and tracks gyro drift at rest.
// Real impacts last several samples and pass the median; knocks on the case
// or I2C glitches of one sample do not.
class ImuFilter {
 public:
  void setCalibration(const ImuCalibration &cal) { cal_ = cal; reset(); }
  const ImuCalibration &calibration() const { return cal_; }
  void reset() { count_ = head_ = 0; stillRun_ = 0; }

  void process(const float raw[Board::CHANNELS], float out[Board::CHANNELS]) {
    float a[3], g[3];
    for (int i = 0; i < 3; ++i) {
      a[i] = raw[i] * cal_.accelScale;
      g[i] = raw[i + 3] - cal_.gyroBias[i];
    }
    trackBias(a, g);
    float *slot = hist_[head_];
    for (int i = 0; i < 3; ++i) {
      slot[i] = cal_.rot[i][0] * a[0] + cal_.rot[i][1] * a[1] + cal_.rot[i][2] * a[2];
      slot[i + 3] = cal_.rot[i][0] * g[0] + cal_.rot[i][1] * g[1] + cal_.rot[i][2] * g[2];
    }
    head_ = (head_ + 1) % 3;
    if (count_ < 3) ++count_;
    for (int c = 0; c < Board::CHANNELS; ++c)
      out[c] = count_ < 3 ? slot[c] : median3(hist_[0][c], hist_[1][c], hist_[2][c]);
  }

 private:
  ImuCalibration cal_;
  float hist_[3][Board::CHANNELS] = {};
  int count_ = 0, head_ = 0, stillRun_ = 0;

  static float median3(float a, float b, float c) {
    if (a > b) { float t = a; a = b; b = t; }
    if (b > c) b = c;
    return a > b ? a : b;
  }
  void trackBias(const float a[3], const float g[3]) {
    const float amag = sqrtf(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
    const float gmag = sqrtf(g[0] * g[0] + g[1] * g[1] + g[2] * g[2]);
    if (gmag < Detect::BIAS_STILL_DPS && fabsf(amag - 1.0f) < Detect::BIAS_STILL_ACC_G) {
      if (stillRun_ < Detect::BIAS_STILL_SAMPLES) ++stillRun_;
    } else {
      stillRun_ = 0;
    }
    if (stillRun_ < Detect::BIAS_STILL_SAMPLES) return;
    for (int i = 0; i < 3; ++i) cal_.gyroBias[i] += Detect::BIAS_TRACK_ALPHA * g[i];
  }
};
