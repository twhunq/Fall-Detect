// ESP32-S3 Super Mini, PCB fall_detector. See README.md for controls/build.
#include <Arduino.h>
#include <stdarg.h>
#include <esp_task_wdt.h>
#include <Preferences.h>
#include <esp_heap_caps.h>
#include <esp_sleep.h>
#include <driver/rtc_io.h>
#include "mbedtls/platform.h"
#include "board_config.h"
#include "mpu6050_i2c.h"
#include "model_inference.h"
#include "runtime_logic.h"
#include "imu_filter.h"
#include "calibration.h"
#include "fall_detector.h"
#include "notifier.h"
#include "device_status.h"
#include "cloud_sync.h"
#include "web_portal.h"
#include "lan_alert_udp.h"
#include "status_led.h"

static MPU6050_I2C mpu;
static SampleWindow window;
static AlertController alert;
static TouchInput touch;
static TapCounter taps;
static ImuFilter filter;
static Calibrator calibrator;
static FallDetector detector;
static InactivityMonitor inactivity;
static Notifier notifier;
static StatusBoard statusBoard;
static WebPortal webPortal;
static CloudSync cloud;
static LanAlertUdp lanAlert;
static uint32_t feedbackAt = 0;
static bool feedbackActive = false, feedbackOk = false;

// NVS record; bump CAL_VERSION whenever ImuCalibration changes layout.
constexpr uint32_t CAL_MAGIC = 0x43414c31; // "CAL1"
constexpr uint16_t CAL_VERSION = 1;
struct StoredCalibration { uint32_t magic; uint16_t version; ImuCalibration cal; };
static bool sensorOnline = false, retryPending = false, modelValid = false;
static uint32_t retryAt = 0, lastSampleMs = 0, readErrors = 0, sampleGaps = 0;
static int fallIndex = -1, prediction = -1;
static float confidence = 0;
static uint32_t batteryMv = 0;
static bool externalPower = true;
static bool wifiOn = false;
static bool batteryLow = false;

// TLS records (16 KB in + 16 KB out per session) go to PSRAM when the board
// has it: the core builds mbedTLS with internal-only allocation, and internal
// RAM cannot hold a TLS session next to Wi-Fi and the web server (seen
// on the board: 6 KB left). Same effect as ESP-IDF's MBEDTLS_EXTERNAL_MEM_ALLOC.
static void *tlsCalloc(size_t n, size_t size) {
  void *p = heap_caps_calloc(n, size, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
  return p ? p : heap_caps_calloc(n, size, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
}

// Best effort USB logging: an absent/slow host must not delay sampling.
static void logLine(const char *format, ...) {
  if (!Serial) return;
  char line[256];
  va_list args;
  va_start(args, format);
  int n = vsnprintf(line, sizeof(line) - 1, format, args);
  va_end(args);
  if (n < 0) return;
  size_t len = static_cast<size_t>(n);
  if (len > sizeof(line) - 2) len = sizeof(line) - 2;
  line[len++] = '\n';
  if (Serial.availableForWrite() >= static_cast<int>(len))
    Serial.write(reinterpret_cast<const uint8_t *>(line), len);
}

// Never turns an active alarm off: only touch acknowledges it.
static void invalidateWindow() {
  window.clear();
  filter.reset();
  detector.reset();
  prediction = -1;
  confidence = 0;
}

static void useCalibration(const ImuCalibration &cal) {
  filter.setCalibration(cal);
  detector = FallDetector{};
  if (cal.valid) {
    const float upright[3] = {0, 0, 1};
    detector.setReference(upright);
  }
}

static void loadCalibration() {
  Preferences prefs;
  StoredCalibration stored = {};
  bool ok = prefs.begin("fallcal", true) &&
            prefs.getBytes("cal", &stored, sizeof(stored)) == sizeof(stored) &&
            stored.magic == CAL_MAGIC && stored.version == CAL_VERSION &&
            stored.cal.valid && stored.cal.finite();
  prefs.end();
  useCalibration(ok ? stored.cal : ImuCalibration{});
  logLine(ok ? "[CAL] Da nap hieu chinh: bias gyro %.2f %.2f %.2f dps, scale %.3f"
             : "[CAL] Chua hieu chinh. Cham 3 lan hoac go 'calib' de hieu chinh.",
          stored.cal.gyroBias[0], stored.cal.gyroBias[1], stored.cal.gyroBias[2], stored.cal.accelScale);
}

static bool saveCalibration(const ImuCalibration *cal) {
  Preferences prefs;
  if (!prefs.begin("fallcal", false)) return false;
  bool ok;
  if (cal) {
    StoredCalibration stored = {CAL_MAGIC, CAL_VERSION, *cal};
    ok = prefs.putBytes("cal", &stored, sizeof(stored)) == sizeof(stored);
  } else {
    ok = !prefs.isKey("cal") || prefs.remove("cal");
  }
  prefs.end();
  return ok;
}

static void startCalibration(uint32_t now) {
  if (!sensorOnline) { logLine("[CAL] Cam bien chua san sang, khong the hieu chinh."); return; }
  if (alert.active) return;
  calibrator.start(now);
  invalidateWindow();
  logLine("[CAL] Deo thiet bi, dung thang va giu yen ~5s...");
}

static void finishCalibration(bool ok, uint32_t now) {
  feedbackActive = true; feedbackOk = ok; feedbackAt = now;
  if (!ok) { logLine("[CAL] That bai: bi rung/sai tu the hoac mat cam bien. Giu nguyen hieu chinh cu."); return; }
  const ImuCalibration &cal = calibrator.result();
  useCalibration(cal);
  bool saved = saveCalibration(&cal);
  logLine("[CAL] OK: bias gyro %.2f %.2f %.2f dps, |g|=%.3f, luu NVS=%s",
          cal.gyroBias[0], cal.gyroBias[1], cal.gyroBias[2], 1.0f / cal.accelScale, saved ? "OK" : "LOI");
}

// Hands the event to the network task; never blocks sensing or the alarm.
static bool notify(NotifyEvent::Kind kind, uint32_t now, float impactG = 0, float postureDeg = 0) {
  NotifyEvent e;
  e.kind = kind;
  e.atMs = now;
  e.impactG = impactG;
  e.postureDeg = postureDeg;
  e.batteryMv = batteryMv;
  return notifier.post(e);
}

static void publishStatus(uint32_t now, bool force = false);

// Fast alert path, before the (slow) TLS channels: status to the web/cloud
// readers at once, UDP burst on the LAN, wake the cloud task. Never blocks.
static void fastAlert(LanAlertKind kind, int32_t metricX100, uint32_t now) {
  publishStatus(now, true);
  if (!wifiOn) return;
  lanAlert.trigger(kind, metricX100, now);
  logLine("[LAN] Phat UDP %u seq=%lu", unsigned(LAN_ALERT_PORT), (unsigned long)lanAlert.seq());
  cloud.wake();
}

// Inactivity alert / "moved again" message.
static void onInactivity(InactivityMonitor::Event event, uint32_t now) {
  if (event == InactivityMonitor::Event::None) return;
  const bool alertNow = event == InactivityMonitor::Event::Alert;
  NotifyEvent e;
  e.kind = alertNow ? NotifyEvent::Kind::Inactive : NotifyEvent::Kind::Resumed;
  e.atMs = now;
  e.stillMin = (alertNow ? inactivity.stillMs(now) : inactivity.endedStillMs()) / 60000;
  e.batteryMv = batteryMv;
  if (alertNow)
    logLine("[INACTIVE] Khong cu dong %lu phut, gui canh bao.", (unsigned long)e.stillMin);
  else
    logLine("[INACTIVE] Da cu dong lai sau %lu phut.", (unsigned long)e.stillMin);
  fastAlert(alertNow ? LanAlertKind::Inactive : LanAlertKind::Resumed, int32_t(e.stillMin) * 100, now);
  notifier.post(e);
}

static void sensorFault() {
  sensorOnline = false;
  invalidateWindow();
  if (calibrator.busy()) { calibrator.cancel(); finishCalibration(false, millis()); }
  retryPending = true;
  retryAt = millis();
  ++readErrors;
  logLine("[MPU] Loi cam bien/I2C/INT; thu lai sau 2s. errors=%lu", (unsigned long)readErrors);
}

static void updateSensor() {
  uint32_t now = millis();
  if (retryPending) {
    if (uint32_t(now - retryAt) < Board::RETRY_MS) return;
    retryPending = false;
    if (!mpu.begin()) { sensorFault(); return; }
  }
  mpu.service(now);
  if (mpu.state() == MPU6050_I2C::State::Failed) { sensorFault(); return; }
  if (!mpu.ready()) return;
  if (!sensorOnline) {
    sensorOnline = true;
    lastSampleMs = millis();
    invalidateWindow();
    inactivity.restart(lastSampleMs);
    logLine("[MPU] OK: 50Hz, SDA8/SCL9/INT7, +-4g, +-500dps");
  }
  MPU6050Data d;
  auto result = mpu.readData(d);
  if (result == MPU6050_I2C::ReadResult::Error) { sensorFault(); return; }
  if (result == MPU6050_I2C::ReadResult::NoData) {
    if (uint32_t(millis() - lastSampleMs) >= Board::SENSOR_STALE_MS) sensorFault();
    return;
  }
  lastSampleMs = millis();
  const float raw[] = {d.ax_g, d.ay_g, d.az_g, d.gx_dps, d.gy_dps, d.gz_dps};
  if (calibrator.busy()) {
    // Calibration consumes raw samples; fall detection resumes afterwards.
    Calibrator::State state = calibrator.update(raw, lastSampleMs);
    if (!calibrator.busy()) finishCalibration(state == Calibrator::State::Done, lastSampleMs);
    return;
  }
  const uint32_t nowUs = micros();
  if (window.gapBefore(nowUs)) { invalidateWindow(); ++sampleGaps; }
  float sample[Board::CHANNELS];
  filter.process(raw, sample);
  // No inactivity alert on top of a fall alarm: that one is already sent.
  const uint32_t limitMs = alert.active ? 0 : uint32_t(notifier.inactiveMinutes()) * 60000UL;
  onInactivity(inactivity.update(sample, lastSampleMs, limitMs), lastSampleMs);
  bool gap = false;
  bool full = window.push(sample, nowUs, gap);
  FallDetector::Verdict verdict = detector.update(sample, lastSampleMs);
  // Candidate under observation: warm up the network path in case it is a fall.
  static bool wasObserving = false;
  const bool observing = detector.observing();
  if (observing && !wasObserving && wifiOn) {
    cloud.prewarm();
    notifier.boost(10000);
  }
  wasObserving = observing;
  if (verdict != FallDetector::Verdict::None) {
    const FallDetector::Report &r = detector.report();
    bool fall = verdict == FallDetector::Verdict::Fall;
    logLine("[FALL?] impact=%.2fg rot=%.0fdps ff=%u ml=%u still=%.0f%% posture=%.0fdeg -> %s",
            r.impactG, r.rotationDps, r.freeFall ? 1u : 0u, r.mlVote ? 1u : 0u,
            r.stillFraction * 100.0f, r.postureDeg, fall ? "NGA" : "bo qua");
    if (fall && alert.trigger(lastSampleMs)) {
      logLine("[ALARM] PHAT HIEN NGA. Cham roi tha de huy.");
      const float g100 = r.impactG * 100.0f + 0.5f;
      fastAlert(LanAlertKind::Fall, g100 > 0 ? (g100 < 100000.0f ? int32_t(g100) : 100000) : 0, lastSampleMs);
      notify(NotifyEvent::Kind::Fall, lastSampleMs, r.impactG, r.postureDeg);
    }
  }
  if (!full || !modelValid) return;
  float features[INPUT_SIZE];
  extractFeatures(window.data, features);
  normalizeFeatures(features);
  prediction = runInference(features, &confidence);
  if (prediction < 0) { modelValid = false; return; }
  detector.onModel(prediction == fallIndex && confidence >= Board::FALL_THRESHOLD, lastSampleMs);
}

// Pins released/isolated around deep sleep (all RTC GPIOs on the S3).
static const gpio_num_t SLEEP_PINS[] = {
    (gpio_num_t)Board::SDA, (gpio_num_t)Board::SCL, (gpio_num_t)Board::MPU_INT,
    (gpio_num_t)Board::BATTERY, (gpio_num_t)Board::LED, (gpio_num_t)Board::BUZZER};

// "Off" = deep sleep: 5V stays connected, so only the ESP32 stops. The TTP223
// (HIGH on touch) wakes it through EXT1: unlike EXT0 it lets the RTC
// peripherals power down (lower sleep current). Never returns.
static void enterDeepSleep() {
  // The WS2812 keeps its last colour; park its data line LOW (not floating).
  pinMode(StatusLed::PIN, OUTPUT);
  digitalWrite(StatusLed::PIN, LOW);
  gpio_hold_en((gpio_num_t)StatusLed::PIN);
  gpio_deep_sleep_hold_en();
  // Isolate holds each pad Hi-Z: no leakage through the GY-521 pull-ups; Q1's
  // base pulldown keeps the buzzer off and the LED is dark.
  for (gpio_num_t pin : SLEEP_PINS) rtc_gpio_isolate(pin);
  rtc_gpio_pullup_dis((gpio_num_t)Board::TOUCH);
  rtc_gpio_pulldown_en((gpio_num_t)Board::TOUCH); // IDF holds it when RTC_PERIPH is off.
  esp_sleep_enable_ext1_wakeup_io(1ULL << Board::TOUCH, ESP_EXT1_WAKEUP_ANY_HIGH);
  esp_deep_sleep_start();
  for (;;) {}
}

// True once the touch pin has read LOW for TOUCH_DEBOUNCE_MS in a row.
static bool touchReleasedStable() {
  static uint32_t lowSince = 0;
  static bool low = false;
  if (digitalRead(Board::TOUCH) == HIGH) { low = false; return false; }
  if (!low) { low = true; lowSince = millis(); }
  return uint32_t(millis() - lowSince) >= Board::TOUCH_DEBOUNCE_MS;
}

static void powerOff() {
  logLine("[POWER] Tat thiet bi (deep sleep). Giu cham 3s de bat lai.");
  digitalWrite(Board::LED, HIGH);
  digitalWrite(Board::BUZZER, HIGH);
  delay(400); // Short enough to block.
  digitalWrite(Board::BUZZER, LOW);
  digitalWrite(Board::LED, LOW);
  // Wait for release, otherwise the still-high pin would wake us at once.
  // Capped so a stuck sensor cannot keep the device awake forever.
  const uint32_t waitStart = millis();
  while (!touchReleasedStable() && uint32_t(millis() - waitStart) < 15000) {
    esp_task_wdt_reset();
    delay(10);
  }
  rgbLedWrite(StatusLed::PIN, 0, 0, 0); // Black first: the WS2812 latches this colour.
  delay(1);
  mpu.sleep(); // Chip SLEEP bit, then Wire.end().
  enterDeepSleep();
}

static void updateTouch(uint32_t now) {
  TouchEvent event = touch.update(digitalRead(Board::TOUCH) == HIGH, now);
  if (event != TouchEvent::None) onInactivity(inactivity.touched(now), now);
  if (event == TouchEvent::Tap && alert.active) {
    alert.acknowledge(now); // Local only: no message is sent on acknowledge.
    taps.clear();
    invalidateWindow();
    logLine("[ALARM] Da huy; tam khoa bao nga 10s, van lay mau.");
  } else if (event == TouchEvent::Tap && !calibrator.busy()) {
    if (taps.tap(now)) startCalibration(now);
  } else if (event == TouchEvent::Hold) {
    powerOff();
  }
}

// Serial commands: "calib" starts calibration, "calib reset" clears it.
static void updateSerial(uint32_t now) {
  static char line[24];
  static uint8_t len = 0;
  for (int budget = 64; budget > 0 && Serial.available() > 0; --budget) {
    int c = Serial.read();
    if (c != '\n' && c != '\r') {
      if (len < sizeof(line) - 1) line[len++] = static_cast<char>(c);
      continue;
    }
    line[len] = '\0';
    if (strcmp(line, "calib") == 0) startCalibration(now);
    else if (strcmp(line, "calib reset") == 0) {
      useCalibration(ImuCalibration{});
      invalidateWindow();
      logLine("[CAL] Da xoa hieu chinh, NVS=%s", saveCalibration(nullptr) ? "OK" : "LOI");
    } else if (strcmp(line, "test notify") == 0) {
      if (!notify(NotifyEvent::Kind::Test, now)) logLine("[NET] Chua cau hinh secrets.h, khong gui duoc.");
    } else if (len) logLine("[CMD] Lenh: calib | calib reset | test notify");
    len = 0;
  }
}

static void updateBattery(uint32_t now) {
  static uint32_t last = 0, sum = 0;
  static uint8_t count = 0, lowCount = 0, highCount = 0;
  if (uint32_t(now - last) < 100) return;
  last = now;
  sum += analogReadMilliVolts(Board::BATTERY);
  if (++count < 16) return;
  batteryMv = static_cast<uint32_t>((sum / 16.0f) * Board::BATTERY_SCALE);
  // USB host present, or no usable battery (an absent battery floats near 2 V).
  externalPower = HWCDC::isPlugged() || batteryMv < 2800;
  notifier.setExternalPower(externalPower);
  sum = 0; count = 0;
  // <2 V: battery absent/switch off. No fabricated charge percentage.
  if (batteryMv < 2000) { batteryLow = false; lowCount = highCount = 0; return; }
  if (batteryMv < Board::BATTERY_LOW_MV) {
    highCount = 0;
    if (lowCount < 3) ++lowCount;
    if (lowCount == 3) batteryLow = true;
  } else if (batteryMv >= Board::BATTERY_RECOVER_MV) {
    lowCount = 0;
    if (highCount < 3) ++highCount;
    if (highCount == 3) batteryLow = false;
  } else { lowCount = highCount = 0; }
}

// Snapshot for the local web page and the cloud (read by tasks on core 0).
static void publishStatus(uint32_t now, bool force) {
  static uint32_t last = 0;
  if (!force && uint32_t(now - last) < 250) return;
  last = now;
  DeviceStatus s;
  s.activity = prediction >= 0 ? CLASS_NAMES[prediction] : nullptr;
  s.confidence = confidence;
  s.alarm = alert.active ? DeviceStatus::Alarm::Fall : DeviceStatus::Alarm::Off;
  s.imuOk = sensorOnline;
  s.modelOk = modelValid;
  s.calValid = filter.calibration().valid;
  s.calRunning = calibrator.busy();
  s.batteryMv = batteryMv;
  s.batteryLow = batteryLow;
  s.readErrors = readErrors;
  s.stillSec = sensorOnline ? inactivity.stillMs(now) / 1000 : 0;
  s.inactive = inactivity.alerted();
  statusBoard.publish(s);
}

// A network task that stays in one step (other than waiting) for 30 s is
// stuck: say where, every 30 s.
static void reportStuck(uint32_t now) {
  static uint32_t last = 0;
  if (uint32_t(now - last) < 30000) return;
  last = now;
  const struct { const char *task; TaskStage *st; } all[] = {
      {"notify", &gStageNotify}, {"cloud", &gStageCloud}};
  for (const auto &a : all) {
    const char *n = (const char *)a.st->name;
    const uint32_t age = now - a.st->since;
    if (age >= 30000 && strcmp(n, "idle") != 0 && strcmp(n, "init") != 0)
      logLine("[KET] Tac vu %s dung o buoc \"%s\" %lu s.", a.task, n, (unsigned long)(age / 1000));
  }
}

// Every minute: heap low-water mark and free stack of the network tasks.
static void logMemory(uint32_t now) {
  static uint32_t last = 0;
  if (uint32_t(now - last) < 60000) return;
  last = now;
  const char *names[] = {"notify", "cloud", "web"};
  unsigned free[3];
  for (int i = 0; i < 3; ++i) {
    TaskHandle_t h = xTaskGetHandle(names[i]);
    free[i] = h ? unsigned(uxTaskGetStackHighWaterMark(h)) : 0;
  }
  logLine("[MEM] RAM noi trong %lu (min %lu), PSRAM trong %lu; stack trong: notify %u cloud %u web %u",
          (unsigned long)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
          (unsigned long)heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL), (unsigned long)ESP.getFreePsram(),
          free[0], free[1], free[2]);
}

// Last resort against heap exhaustion (seen once on the board, cause not
// found): with no TLS-sized block left for a minute the network cannot work
// any more. Restart, but never during an alarm or calibration.
static void heapGuard(uint32_t now) {
  static uint32_t lowSince = 0;
  if (ESP.getMaxAllocHeap() >= 16000) { lowSince = 0; return; }
  if (!lowSince) {
    lowSince = now | 1;
    logLine("[MEM] RAM thap: trong %lu, khoi lon nhat %lu.", (unsigned long)ESP.getFreeHeap(),
            (unsigned long)ESP.getMaxAllocHeap());
    return;
  }
  if (uint32_t(now - lowSince) < 90000 || alert.active || calibrator.busy()) return;
  logLine("[MEM] RAM can kiet qua 90 giay, khoi dong lai de phuc hoi.");
  delay(50);
  ESP.restart();
}

// On-board RGB LED shows the network state (status_led.h); written only on change.
static void updateNetLed(uint32_t now) {
  static StatusLed::Rgb shown;
  static bool written = false;
  const StatusLed::Net s = StatusLed::state(wifiOn, notifier.net() == Notifier::Net::Online, notifier.apActive(),
                                            CloudSync::configured(), cloud.state() == CloudSync::State::Online);
  const StatusLed::Rgb c = StatusLed::color(s, now);
  if (written && c == shown) return;
  rgbLedWrite(StatusLed::PIN, c.r, c.g, c.b);
  shown = c;
  written = true;
}

static void updateOutputs(uint32_t now) {
  bool led = false, buzzer = false;
  if (feedbackActive && uint32_t(now - feedbackAt) >= 800) feedbackActive = false;
  if (alert.active) {
    led = true;
    buzzer = (uint32_t(now - alert.started) % 600) < 300;
  } else if (calibrator.busy()) {
    led = (now % 200) < 100; // Fast blink: keep still.
  } else if (feedbackActive) {
    // Calibration result: two short beeps = OK, one long beep = failed.
    uint32_t t = now - feedbackAt;
    led = buzzer = feedbackOk ? (t < 100 || (t >= 200 && t < 300)) : t < 800;
  } else if (!sensorOnline || !modelValid) {
    uint32_t phase = now % 2000;
    led = phase < 100 || (phase >= 200 && phase < 300) || (phase >= 400 && phase < 500);
  } else if (batteryLow) {
    uint32_t phase = now % 3000;
    led = phase < 100 || (phase >= 200 && phase < 300);
  } else led = (now % 2000) < 40;
  digitalWrite(Board::LED, led ? HIGH : LOW);
  digitalWrite(Board::BUZZER, buzzer ? HIGH : LOW);
}

void setup() {
  // Undo enterDeepSleep(): release holds and the RTC mux, then drive outputs LOW
  // at once (the buzzer stays off meanwhile through Q1's base pulldown).
  for (gpio_num_t pin : SLEEP_PINS) { gpio_hold_dis(pin); rtc_gpio_deinit(pin); }
  gpio_hold_dis((gpio_num_t)StatusLed::PIN);
  gpio_deep_sleep_hold_dis();
  digitalWrite(Board::BUZZER, LOW); pinMode(Board::BUZZER, OUTPUT);
  digitalWrite(Board::LED, LOW); pinMode(Board::LED, OUTPUT);
  if (esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_EXT1) {
    // Woken by touch: switch on only if it is held for POWER_HOLD_MS, else sleep again.
    rtc_gpio_deinit((gpio_num_t)Board::TOUCH);
    pinMode(Board::TOUCH, INPUT_PULLDOWN);
    while (millis() < Board::POWER_HOLD_MS) {
      if (touchReleasedStable()) enterDeepSleep(); // Short touch: stay off, no beep.
      delay(5);
    }
    for (int i = 0; i < 2; ++i) { // Two short beeps = on.
      digitalWrite(Board::LED, HIGH); digitalWrite(Board::BUZZER, HIGH); delay(100);
      digitalWrite(Board::LED, LOW); digitalWrite(Board::BUZZER, LOW); delay(100);
    }
  }
  pinMode(Board::TOUCH, INPUT_PULLDOWN);
  pinMode(Board::MPU_INT, INPUT_PULLDOWN);
  pinMode(Board::BATTERY, INPUT);
  analogReadResolution(12);
  analogSetPinAttenuation(Board::BATTERY, ADC_11db);
  Serial.setTxBufferSize(4096); // The 64-byte USB FIFO alone dropped most network log lines.
  Serial.begin(115200);
  Serial.setTxTimeoutMs(0);
  const bool psram = psramFound();
  if (psram) mbedtls_platform_set_calloc_free(tlsCalloc, free); // Before any TLS session.
  // No wait for USB: this device must work on battery alone.
  for (int i = 0; i < OUTPUT_SIZE; ++i)
    if (strcmp(CLASS_NAMES[i], "nga") == 0) fallIndex = i;
  modelValid = fallIndex >= 0;
  for (int i = 0; i < INPUT_SIZE; ++i)
    if (!isfinite(FEATURE_STD[i]) || FEATURE_STD[i] <= 0 || !isfinite(FEATURE_MEAN[i]))
      modelValid = false;
  esp_task_wdt_config_t watchdog = {};
  watchdog.timeout_ms = 5000;
  watchdog.idle_core_mask = 0;
  watchdog.trigger_panic = true;
  esp_err_t wdt = esp_task_wdt_init(&watchdog);
  if (wdt == ESP_ERR_INVALID_STATE) wdt = esp_task_wdt_reconfigure(&watchdog);
  if (wdt == ESP_OK) enableLoopWDT();
  else logLine("[WDT] Khong bat duoc watchdog: %d", static_cast<int>(wdt));
  logLine("TinyML ESP32-S3 | touch4 buzzer5 LED6 battery1 | reset=%d | PSRAM %s", static_cast<int>(esp_reset_reason()),
          psram ? "OK (TLS, Wi-Fi o PSRAM)" : "khong co");
  loadCalibration();
  wifiOn = notifier.begin();
  if (wifiOn) {
    bool web = webPortal.begin(notifier, statusBoard, cloud, &lanAlert);
    logLine("[NET] Bat Wi-Fi: canh bao Telegram/Gmail, trang web %s (http://" WEB_HOSTNAME ".local).",
            web ? "OK" : "LOI");
    if (!*WEB_PASSWORD) logLine("[NET] Trang web khong co mat khau (WEB_PASSWORD trong secrets.h).");
    if (!CloudSync::configured()) logLine("[CLOUD] Tat (chua co FIREBASE_* trong secrets.h).");
    else if (!cloud.begin(notifier, statusBoard)) logLine("[CLOUD] Khong tao duoc task dong bo.");
  } else logLine("[NET] Tat Wi-Fi (chua luu mang nao va WIFI_SETUP_AP = 0).");
  if (!mpu.begin()) sensorFault();
}

void loop() {
  updateTouch(millis());
  updateSerial(millis());
  char netLog[120];
  if (notifier.nextLog(netLog, sizeof(netLog))) logLine("%s", netLog);
  updateSensor();
  lanAlert.poll(millis());
  updateOutputs(millis());
  updateNetLed(millis());
  updateBattery(millis());
  publishStatus(millis());
  heapGuard(millis());
  logMemory(millis());
  reportStuck(millis());
  static uint32_t lastLog = 0;
  uint32_t now = millis();
  if (uint32_t(now - lastLog) >= 1000) {
    lastLog = now;
    logLine("[STATUS] imu=%s model=%s cal=%s det=%s net=%s cloud=%s pred=%s conf=%.1f%% alarm=%s bat=%lumV low=%u err=%lu gap=%lu heap=%lu/%lu still=%lus%s",
            sensorOnline ? "OK" : "FAULT", modelValid ? "OK" : "FAULT",
            calibrator.busy() ? "RUN" : (filter.calibration().valid ? "OK" : "NONE"),
            detector.observing() ? "OBS" : "IDLE",
            notifier.net() == Notifier::Net::Online ? "OK"
                : (notifier.net() == Notifier::Net::Connecting ? "WAIT" : "OFF"),
            cloud.state() == CloudSync::State::Online ? "OK"
                : cloud.state() == CloudSync::State::Connecting ? "WAIT"
                : cloud.state() == CloudSync::State::AuthError ? "AUTH" : "OFF",
            prediction >= 0 ? CLASS_NAMES[prediction] : "--", confidence * 100.0f,
            alert.active ? "FALL" : "OFF",
            (unsigned long)batteryMv, batteryLow ? 1u : 0u,
            (unsigned long)readErrors, (unsigned long)sampleGaps, (unsigned long)ESP.getFreeHeap(),
            (unsigned long)ESP.getMaxAllocHeap(), 
            (unsigned long)(sensorOnline ? inactivity.stillMs(now) / 1000 : 0),
            inactivity.alerted() ? " BAT_DONG" : "");
  }
  delay(1); // Yield to FreeRTOS and USB; no busy-wait or heap allocation in loop.
}
