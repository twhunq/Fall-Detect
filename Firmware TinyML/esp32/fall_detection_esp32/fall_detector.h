#pragma once
#include <math.h>
#include <stdint.h>
#include "board_config.h"
#include "detection_config.h"

// Physical fall confirmation around the ML model. Light movement never opens a
// candidate because it has no impact peak; a candidate becomes a fall only if
// it has supporting evidence and the wearer then stays still in a new posture
// (lying after standing/sitting). Getting up or moving again rejects it.
class FallDetector {
 public:
  enum class Verdict { None, Fall, Rejected };
  struct Report {
    float impactG = 0, rotationDps = 0, stillFraction = 0, postureDeg = 0;
    bool freeFall = false, mlVote = false;
  };

  bool observing() const { return observing_; }
  const Report &report() const { return report_; }

  // Sensor gap/fault: an interrupted observation cannot be confirmed.
  void reset() { observing_ = false; rotationPeak_ = 0; freeFallSeen_ = false; }
  // Upright gravity direction from calibration (+Z in the calibrated frame).
  void setReference(const float g[3]) {
    for (int i = 0; i < 3; ++i) ref_[i] = g[i];
    haveRef_ = true;
  }

  // Filtered, calibrated sample: ax, ay, az [g], gx, gy, gz [deg/s].
  Verdict update(const float s[Board::CHANNELS], uint32_t now) {
    const float amag = norm(s), gmag = norm(s + 3);
    rotationPeak_ = fmaxf(gmag, rotationPeak_ * Detect::ROTATION_PEAK_DECAY);
    if (amag < Detect::FREEFALL_G) { freeFallSeen_ = true; lastFreeFall_ = now; }
    if (!observing_) {
      updateReference(s, amag, gmag);
      if (amag >= Detect::IMPACT_G) begin(amag, now);
      return Verdict::None;
    }
    const uint32_t elapsed = now - impact_;
    report_.impactG = fmaxf(report_.impactG, amag);
    if (elapsed <= Detect::ML_VOTE_MS) report_.rotationDps = fmaxf(report_.rotationDps, rotationPeak_);
    if (elapsed < Detect::SETTLE_MS) return Verdict::None;
    ++total_;
    if (fabsf(amag - 1.0f) < Detect::STILL_ACC_G && gmag < Detect::STILL_GYRO_DPS) ++still_;
    for (int i = 0; i < 3; ++i) after_[i] += s[i];
    if (elapsed < Detect::SETTLE_MS + Detect::OBSERVE_MS) return Verdict::None;
    return decide();
  }

  // ML result for the latest window; only votes shortly after an impact count.
  void onModel(bool fall, uint32_t now) {
    if (fall && observing_ && uint32_t(now - impact_) <= Detect::ML_VOTE_MS) report_.mlVote = true;
  }

 private:
  bool observing_ = false, haveRef_ = false, freeFallSeen_ = false;
  float ref_[3] = {0, 0, 1}, before_[3] = {0, 0, 1}, after_[3] = {};
  float rotationPeak_ = 0;
  uint32_t impact_ = 0, lastFreeFall_ = 0;
  int still_ = 0, total_ = 0;
  Report report_;

  static float norm(const float *v) { return sqrtf(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]); }

  void updateReference(const float s[], float amag, float gmag) {
    if (fabsf(amag - 1.0f) >= Detect::REF_ACC_TOL_G || gmag >= Detect::STILL_GYRO_DPS) return;
    float n = 0;
    for (int i = 0; i < 3; ++i) {
      ref_[i] = haveRef_ ? ref_[i] + Detect::REF_ALPHA * (s[i] / amag - ref_[i]) : s[i] / amag;
      n += ref_[i] * ref_[i];
    }
    n = sqrtf(n);
    for (int i = 0; i < 3; ++i) ref_[i] /= n;
    haveRef_ = true;
  }

  void begin(float amag, uint32_t now) {
    observing_ = true;
    impact_ = now;
    report_ = Report{};
    report_.impactG = amag;
    report_.rotationDps = rotationPeak_;
    report_.freeFall = freeFallSeen_ && uint32_t(now - lastFreeFall_) <= Detect::FREEFALL_LOOKBACK_MS;
    for (int i = 0; i < 3; ++i) { before_[i] = ref_[i]; after_[i] = 0; }
    still_ = total_ = 0;
  }

  Verdict decide() {
    observing_ = false;
    report_.stillFraction = total_ ? float(still_) / total_ : 0.0f;
    const float n = norm(after_);
    float cosine = n > 1e-3f ? (after_[0] * before_[0] + after_[1] * before_[1] + after_[2] * before_[2]) / n : 1.0f;
    cosine = fminf(1.0f, fmaxf(-1.0f, cosine));
    report_.postureDeg = acosf(cosine) * 57.2957795f;
    const bool evidence = report_.freeFall || report_.mlVote || report_.rotationDps >= Detect::ROTATION_DPS;
    const bool down = report_.stillFraction >= Detect::STILL_FRACTION &&
                      report_.postureDeg >= Detect::POSTURE_CHANGE_DEG;
    return evidence && down ? Verdict::Fall : Verdict::Rejected;
  }
};
