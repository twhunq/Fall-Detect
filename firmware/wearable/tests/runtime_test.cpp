#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdio.h>
#include <fstream>
#include "runtime_logic.h"
#include "model_inference.h"

static void checkLogic() {
  SampleWindow w;
  float row[6] = {0, 0, 1, 0, 0, 0};
  bool gap;
  uint32_t us = UINT32_MAX - 400000;
  for (int i = 0; i < 50; ++i) {
    assert(w.push(row, us, gap) == (i == 49));
    assert(!gap); us += 20000;
  }
  for (int i = 0; i < 10; ++i) {
    assert(w.push(row, us, gap) == (i == 9));
    assert(!gap); us += 20000;
  }
  assert(!w.push(row, us + 40000, gap) && gap);
  for (int i = 1; i < 50; ++i)
    assert(w.push(row, us + 40000 + i * 20000, gap) == (i == 49));

  AlertController a;
  assert(a.trigger(600) && a.active && a.started == 600);
  assert(!a.trigger(700) && a.started == 600); // Latched, not restarted.
  uint32_t now = UINT32_MAX - 5000;
  a.acknowledge(now);
  assert(!a.active);
  assert(!a.trigger(now + 9999)); // Inhibit across millis() wrap.
  assert(a.trigger(now + 10000) && a.active);

  TapCounter taps;
  assert(!taps.tap(1000) && !taps.tap(1400) && taps.tap(1900));
  assert(!taps.tap(5000) && !taps.tap(5500) && !taps.tap(7000)); // Too slow: restarts.
  assert(!taps.tap(7400) && taps.tap(7600));
  taps.tap(9000); taps.clear();
  assert(!taps.tap(9100) && !taps.tap(9200) && taps.tap(9300));

  TouchInput t;
  assert(t.update(true, 0) == TouchEvent::None);
  assert(t.update(true, 1600) == TouchEvent::None);
  assert(t.update(false, 1700) == TouchEvent::None);
  assert(t.update(false, 1740) == TouchEvent::None); // Arm after release.
  t.update(true, 1800); t.update(false, 1810); t.update(false, 1850); // Bounce.
  t.update(true, 2000); t.update(true, 2040);
  t.update(false, 2100);
  assert(t.update(false, 2140) == TouchEvent::Tap);
  assert(t.update(false, 2180) == TouchEvent::None);
  t.update(true, 2200); t.update(true, 2240);
  assert(t.update(true, 5239) == TouchEvent::None);
  assert(t.update(true, 5240) == TouchEvent::Hold);
  assert(t.update(true, 9000) == TouchEvent::None);
  t.update(false, 9010);
  assert(t.update(false, 9050) == TouchEvent::None); // Releasing after Hold gives no Tap.
  t.update(true, UINT32_MAX - 100);
  t.update(true, UINT32_MAX - 60);
  assert(t.update(true, 2940) == TouchEvent::Hold);

  float features[INPUT_SIZE] = {};
  float conf = 1;
  features[0] = NAN;
  assert(runInference(features, &conf) == -1 && conf == 0);
}

int main(int argc, char **argv) {
  checkLogic();
  assert(argc == 2);
  std::ifstream f(argv[1], std::ios::binary);
  assert(f.good());
  int windows = 0;
  float rows[50][6], expected[30], normalized[30], result[2];
  while (f.read(reinterpret_cast<char *>(rows), sizeof(rows))) {
    f.read(reinterpret_cast<char *>(expected), sizeof(expected));
    f.read(reinterpret_cast<char *>(normalized), sizeof(normalized));
    f.read(reinterpret_cast<char *>(result), sizeof(result));
    assert(f.good());
    float actual[30];
    extractFeatures(rows, actual);
    for (int i = 0; i < 30; ++i)
      assert(fabsf(actual[i] - expected[i]) <= 0.0002f + fabsf(expected[i]) * 0.00002f);
    normalizeFeatures(actual);
    for (int i = 0; i < 30; ++i) {
      if (fabsf(actual[i] - normalized[i]) > 0.0005f + fabsf(normalized[i]) * 0.00002f)
        fprintf(stderr, "window=%d feature=%d actual=%.9g expected=%.9g\n", windows, i, actual[i], normalized[i]);
      assert(fabsf(actual[i] - normalized[i]) <= 0.0005f + fabsf(normalized[i]) * 0.00002f);
    }
    float conf;
    int prediction = runInference(actual, &conf);
    assert(prediction == static_cast<int>(result[0]));
    assert(fabsf(conf - result[1]) < 0.0001f);
    // Rotating the ring must not alter the output statistics/classification.
    float rotated[50][6];
    for (int s = 0; s < 50; ++s)
      for (int c = 0; c < 6; ++c) rotated[s][c] = rows[(s + 17) % 50][c];
    extractFeatures(rotated, actual); normalizeFeatures(actual);
    assert(runInference(actual, &conf) == prediction);
    assert(fabsf(conf - result[1]) < 0.0001f);
    ++windows;
  }
  assert(windows >= 600);
  printf("PASS: runtime edge cases + Python/C++ parity on %d windows\n", windows);
}
