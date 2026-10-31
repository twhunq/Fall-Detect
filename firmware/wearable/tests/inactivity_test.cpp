#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <random>
#include "imu_filter.h"
#include "runtime_logic.h"

constexpr double PI_D = 3.14159265358979;

// Synthetic wearer lying still: breathing tilts the torso (accelerometer),
// each heartbeat shakes the chest (gyro bursts), plus MPU6050-level noise,
// accelerometer offset and gyro bias. None of this is movement.
struct Body {
  float heartBpm = 72, breathBpm = 15;
  float heartDps = 1.5f, breathG = 0.012f;
  float accNoiseG = 0.004f, gyroNoiseDps = 0.05f;
  float moveDps = 0; // > 0: walking-like movement
  std::mt19937 rng{1234};
  std::normal_distribution<float> gauss{0.0f, 1.0f};

  static float burst(float tau) {
    if (tau < 0 || tau > 0.2f) return 0;
    return float(sin(2 * PI_D * 9.0 * tau) * exp(-tau / 0.04));
  }
  void sample(double t, float raw[6]) {
    const float br = breathG * float(sin(2 * PI_D * breathBpm / 60.0 * t));
    const float tau = float(fmod(t, 60.0 / heartBpm));
    const float beat = heartDps * (burst(tau) + 0.5f * burst(tau - 0.3f));
    const float walk = moveDps * float(sin(2 * PI_D * 1.8 * t));
    raw[0] = 0.02f + br + 0.005f * walk + accNoiseG * gauss(rng);
    raw[1] = -0.03f + 0.4f * br + accNoiseG * gauss(rng);
    raw[2] = 1.03f + 0.003f * walk + accNoiseG * gauss(rng);
    raw[3] = 1.8f + beat + walk + gyroNoiseDps * gauss(rng);
    raw[4] = -0.7f + 0.6f * beat + 0.5f * walk + gyroNoiseDps * gauss(rng);
    raw[5] = 0.4f + 0.3f * beat + gyroNoiseDps * gauss(rng);
  }
};

// 50 Hz samples through the real filter; millis() wraps during the run.
struct Rig {
  Body body;
  ImuFilter filter;
  InactivityMonitor still;
  double t = 0;
  int alerts = 0, resumes = 0;
  uint32_t ms() const { return UINT32_MAX - 20000 + uint32_t(t * 1000); }

  void run(double seconds, uint32_t limitMs) {
    for (double end = t + seconds; t < end; t += 0.02) {
      float raw[6], s[6];
      body.sample(t, raw);
      filter.process(raw, s);
      InactivityMonitor::Event e = still.update(s, ms(), limitMs);
      alerts += e == InactivityMonitor::Event::Alert;
      resumes += e == InactivityMonitor::Event::Resumed;
    }
  }
};

int main() {
  // Breathing and heartbeat are not movement: a still wearer raises one alert.
  Rig r;
  r.run(59, 60000);
  assert(r.alerts == 0 && r.still.stillMs(r.ms()) >= 58000);
  r.run(2, 60000);
  assert(r.alerts == 1 && r.still.alerted());
  r.run(120, 60000);
  assert(r.alerts == 1); // Not repeated while the wearer stays still.
  r.body.moveDps = 40;
  r.run(0.5, 60000);
  assert(r.resumes == 1 && !r.still.alerted());
  assert(r.still.endedStillMs() >= 180000 && r.still.endedStillMs() < 183000);
  r.body.moveDps = 0;
  r.run(30, 60000);
  assert(r.alerts == 1 && r.still.stillMs(r.ms()) < 31000); // Counting again from the movement.

  // Limit 0 (off, or an alarm already active): never alerts.
  Rig off;
  off.run(120, 0);
  assert(off.alerts == 0 && !off.still.alerted());

  // A touch on the device counts as movement and ends an alert.
  InactivityMonitor m;
  const float rest[6] = {0, 0, 1, 0, 0, 0};
  m.restart(UINT32_MAX - 1000);
  assert(m.update(rest, UINT32_MAX - 1000 + 59999, 60000) == InactivityMonitor::Event::None);
  assert(m.update(rest, UINT32_MAX - 1000 + 60000, 60000) == InactivityMonitor::Event::Alert); // millis wrap
  assert(m.touched(70000) == InactivityMonitor::Event::Resumed && !m.alerted());
  assert(m.touched(70100) == InactivityMonitor::Event::None);

  // Two loud samples are a glitch, three are movement.
  m.restart(0);
  const float jolt[6] = {0, 0, 1, 80, 0, 0};
  for (uint32_t t = 0; t < 1000; t += 20) m.update(rest, t, 0);
  m.update(jolt, 1000, 0);
  m.update(jolt, 1020, 0);
  m.update(rest, 1040, 0);
  assert(m.stillMs(1040) == 1040);
  m.update(jolt, 1060, 0);
  m.update(jolt, 1080, 0);
  m.update(jolt, 1100, 0);
  assert(m.stillMs(1100) == 0);

  // Back online after a sensor fault: a fresh count, but an alert already
  // sent is neither repeated nor forgotten.
  InactivityMonitor f;
  f.restart(0);
  assert(f.update(rest, 60000, 60000) == InactivityMonitor::Event::Alert);
  f.restart(100000);
  assert(f.alerted() && f.update(rest, 200000, 60000) == InactivityMonitor::Event::None);
  puts("PASS: inactivity monitor: limit, single alert, resume, touch, glitches, wrap");
}
