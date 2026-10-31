#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "imu_filter.h"
#include "calibration.h"
#include "fall_detector.h"

static bool near(float a, float b, float tol) { return fabsf(a - b) <= tol; }

// Feeds filter -> detector at 50 Hz, as the firmware does.
struct Sim {
  ImuFilter filter;
  FallDetector detector;
  uint32_t ms = 0;
  int falls = 0, rejected = 0, samples = 0;
  bool mlFall = false;
  void step(float ax, float ay, float az, float gx, float gy, float gz) {
    const float raw[6] = {ax, ay, az, gx, gy, gz};
    float s[6];
    filter.process(raw, s);
    FallDetector::Verdict v = detector.update(s, ms);
    if (v == FallDetector::Verdict::Fall) ++falls;
    if (v == FallDetector::Verdict::Rejected) ++rejected;
    if (++samples % Board::HOP_SIZE == 0) detector.onModel(mlFall, ms);
    ms += 20;
  }
  void hold(float seconds, float ax, float ay, float az) {
    for (int i = 0; i < int(seconds * 50); ++i)
      step(ax + 0.005f * sinf(i * 1.3f), ay, az + 0.005f * cosf(i * 0.7f), 0.3f * sinf(i * 0.9f), 0, 0);
  }
  void fallDown(bool freeFall, float spinDps) {
    for (int i = 0; i < 20; ++i) step(0, 0, freeFall ? 0.3f : 0.8f, spinDps, spinDps * 0.3f, 0);
    step(1.2f, 0, 3.0f, 80, 0, 0); // Impact, several samples wide.
    step(0.9f, 0, 2.4f, 40, 0, 0);
    step(0.6f, 0, 1.5f, 20, 0, 0);
  }
  void walk(float seconds) {
    for (int i = 0; i < int(seconds * 50); ++i) {
      float t = i * 0.02f;
      step(0.2f * sinf(12.6f * t), 0.15f * cosf(12.6f * t), 1.0f + 0.45f * sinf(12.6f * t),
           70 * sinf(12.6f * t), 40 * cosf(12.6f * t), 10 * sinf(25.f * t));
    }
  }
};

static void checkAlignment() {
  const float vectors[][3] = {{0, 0, 1}, {0, 0, -1}, {1, 0, 0}, {0, -1, 0}, {0.6f, 0.48f, -0.64f}, {-0.1f, 0.2f, 0.97467943f}};
  for (const auto &u : vectors) {
    float r[3][3];
    alignToZ(u, r);
    for (int i = 0; i < 3; ++i) {
      float z = r[i][0] * u[0] + r[i][1] * u[1] + r[i][2] * u[2];
      assert(near(z, i == 2 ? 1.0f : 0.0f, 1e-5f));
      for (int j = 0; j < 3; ++j) { // Orthonormal rows.
        float dot = r[i][0] * r[j][0] + r[i][1] * r[j][1] + r[i][2] * r[j][2];
        assert(near(dot, i == j ? 1.0f : 0.0f, 1e-5f));
      }
    }
  }
}

static void checkFilter() {
  ImuFilter f;
  float out[6];
  const float spike[] = {1, 1, 5, 1, 1, 1};
  for (float v : spike) {
    const float raw[6] = {0, 0, v, 0, 0, 0};
    f.process(raw, out);
    assert(out[2] < 1.5f); // One-sample glitch removed.
  }
  float peak = 0;
  const float impact[] = {1, 1, 5, 4, 1, 1};
  for (float v : impact) {
    const float raw[6] = {0, 0, v, 0, 0, 0};
    f.process(raw, out);
    peak = fmaxf(peak, out[2]);
  }
  assert(peak == 4); // Multi-sample peak kept.

  ImuFilter drift; // Gyro drift tracked only while motionless.
  for (int i = 0; i < 2000; ++i) {
    const float raw[6] = {0, 0, 1, 1.0f, -0.5f, 0, };
    drift.process(raw, out);
  }
  assert(near(out[3], 0, 0.05f) && near(out[4], 0, 0.05f));
  const float bias = drift.calibration().gyroBias[0];
  for (int i = 0; i < 500; ++i) {
    const float raw[6] = {0.3f, 0, 1.2f, 60, 0, 0};
    drift.process(raw, out);
  }
  assert(drift.calibration().gyroBias[0] == bias);
}

static Calibrator::State runCalibration(Calibrator &c, const float a[3], const float bias[3],
                                        float motionDps, uint32_t motionUntilMs) {
  c.start(0);
  for (uint32_t ms = 0; ms < 30000 && c.busy(); ms += 20) {
    float wobble = ms < motionUntilMs ? motionDps * sinf(ms * 0.01f) : 0.0f;
    const float raw[6] = {a[0] + 0.004f * sinf(ms * 0.3f), a[1], a[2] + 0.004f * cosf(ms * 0.2f),
                          bias[0] + 0.5f * sinf(ms * 0.7f) + wobble, bias[1], bias[2] - wobble};
    c.update(raw, ms);
  }
  return c.state();
}

static void checkCalibration() {
  const float bias[3] = {2.0f, -1.5f, 0.7f};
  const float sideways[3] = {0.97f, 0.12f, 0.1f}; // Mounted rotated, |g| ~ 0.98.
  Calibrator c;
  assert(runCalibration(c, sideways, bias, 0, 0) == Calibrator::State::Done);
  ImuFilter f;
  f.setCalibration(c.result());
  float out[6];
  for (int i = 0; i < 5; ++i) {
    const float raw[6] = {sideways[0], sideways[1], sideways[2], bias[0], bias[1], bias[2]};
    f.process(raw, out);
  }
  assert(near(out[0], 0, 0.01f) && near(out[1], 0, 0.01f) && near(out[2], 1, 0.01f));
  assert(near(out[3], 0, 0.05f) && near(out[4], 0, 0.05f) && near(out[5], 0, 0.05f));

  const float upsideDown[3] = {0, 0, -1};
  assert(runCalibration(c, upsideDown, bias, 0, 0) == Calibrator::State::Done);
  assert(near(c.result().rot[2][2], -1, 1e-5f));

  const float upright[3] = {0, 0, 1};
  assert(runCalibration(c, upright, bias, 25, 30000) == Calibrator::State::Failed); // Never still.
  assert(runCalibration(c, upright, bias, 25, 6000) == Calibrator::State::Done);   // Still later.
  const float light[3] = {0, 0, 0.5f};
  assert(runCalibration(c, light, bias, 0, 0) == Calibrator::State::Failed);
  const float zero[3] = {0, 0, 0};
  assert(runCalibration(c, upright, zero, 0, 0) == Calibrator::State::Done);
  c.start(0); c.cancel();
  assert(c.state() == Calibrator::State::Failed && !c.busy());
}

static void checkScenarios() {
  { // Real fall: free fall + spin + impact, then lying still.
    Sim s; s.hold(2, 0.01f, 0, 1);
    s.fallDown(true, 150);
    s.hold(1.0f, 1, 0, 0.05f);
    assert(s.detector.observing() && s.falls == 0); // Waits for confirmation.
    s.hold(3, 1, 0, 0.05f);
    assert(s.falls == 1 && s.rejected == 0);
    assert(s.detector.report().freeFall && s.detector.report().postureDeg > 80);
  }
  { // Light movement with the ML model wrongly voting "nga" all the time.
    Sim s; s.mlFall = true; s.hold(2, 0, 0, 1);
    for (int i = 0; i < 500; ++i) {
      float t = i * 0.02f;
      s.step(0.3f * sinf(3 * t), 0.2f * cosf(5 * t), 1 + 0.3f * sinf(9 * t), 90 * sinf(4 * t), 60 * cosf(6 * t), 30 * sinf(7 * t));
    }
    assert(s.falls == 0 && s.rejected == 0 && !s.detector.observing());
  }
  { // Walking for a while never opens a candidate.
    Sim s; s.mlFall = true; s.hold(2, 0, 0, 1); s.walk(10);
    assert(s.falls == 0 && s.rejected == 0);
  }
  { // Sitting down hard: impact but only a small posture change.
    Sim s; s.mlFall = true; s.hold(2, 0, 0, 1);
    s.fallDown(false, 60);
    s.hold(4, 0.34f, 0, 0.94f); // ~20 degrees.
    assert(s.falls == 0 && s.rejected == 1);
  }
  { // Fall-like impact, then the wearer gets up and walks away.
    Sim s; s.hold(2, 0, 0, 1);
    s.fallDown(true, 150);
    s.hold(0.8f, 1, 0, 0);
    s.walk(3);
    assert(s.falls == 0 && s.rejected == 1);
  }
  { // Knock on the case: one-sample spike is filtered, no candidate.
    Sim s; s.hold(2, 0, 0, 1);
    s.step(0.5f, 0, 3.5f, 5, 0, 0);
    s.hold(4, 0, 0, 1);
    assert(s.falls == 0 && s.rejected == 0);
  }
  { // Impact + lying, but no free fall/spin: needs the ML vote.
    Sim s; s.hold(2, 0, 0, 1);
    s.fallDown(false, 30);
    s.hold(4, 1, 0, 0);
    assert(s.falls == 0 && s.rejected == 1);
    Sim m; m.mlFall = true; m.hold(2, 0, 0, 1);
    m.fallDown(false, 30);
    m.hold(4, 1, 0, 0);
    assert(m.falls == 1 && m.detector.report().mlVote);
  }
  { // Sensor gap during observation aborts the candidate.
    Sim s; s.hold(2, 0, 0, 1);
    s.fallDown(true, 150);
    s.detector.reset(); s.filter.reset();
    s.hold(4, 1, 0, 0);
    assert(s.falls == 0 && s.rejected == 0);
  }
  { // Uncalibrated device mounted sideways: reference learned from wear.
    Sim s; s.hold(3, 1, 0, 0.02f);
    for (int i = 0; i < 20; ++i) s.step(0.2f, 0, 0, 0, 150, 0);
    s.step(3.0f, 0.5f, 0.5f, 80, 0, 0); s.step(2.4f, 0, 0.6f, 40, 0, 0); s.step(1.5f, 0, 0.5f, 0, 0, 0);
    s.hold(4, 0.05f, 0, 1);
    assert(s.falls == 1);
  }
  { // Timer wrap during observation.
    Sim s; s.ms = UINT32_MAX - 2500; s.hold(2, 0, 0, 1);
    s.fallDown(true, 150);
    s.hold(4, 1, 0, 0);
    assert(s.falls == 1);
  }
}

int main() {
  checkAlignment();
  checkFilter();
  checkCalibration();
  checkScenarios();
  puts("PASS: calibration, median/bias filter and fall confirmation scenarios");
}
