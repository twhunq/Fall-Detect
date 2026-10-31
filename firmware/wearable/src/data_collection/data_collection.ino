// Real-data collection with the SAME pins, filter, rate and ranges as detection.
#include <Arduino.h>
#include "board_config.h"
#include "mpu6050_i2c.h"

static MPU6050_I2C mpu;
static float samples[Board::WINDOW_SIZE][Board::CHANNELS];
static char input[16] = {}, label[16] = {};
static size_t inputSize = 0;
static bool inputOverflow = false, online = false, retry = false, collecting = false;
static uint32_t retryAt = 0, lastData = 0, lastUs = 0;
static int count = 0;
static char csv[4096];
static size_t csvSize = 0, csvSent = 0;

static void message(const char *s) {
  if (csvSize) return; // Do not interleave status messages with a CSV record.
  size_t n = strlen(s);
  if (Serial && Serial.availableForWrite() >= static_cast<int>(n + 1)) {
    Serial.write(reinterpret_cast<const uint8_t *>(s), n); Serial.write('\n');
  }
}
static void failSensor() {
  collecting = online = false; count = 0;
  retry = true; retryAt = millis();
  message("[LOI] MPU/I2C/INT. Huy cua so, thu lai sau 2s.");
}
static bool validLabel(const char *s) {
  return !strcmp(s, "dung") || !strcmp(s, "ngoi") || !strcmp(s, "nam") ||
         !strcmp(s, "di_bo") || !strcmp(s, "nga");
}
static void readCommand() {
  // Bound work even if the host floods USB. Never wait for a newline.
  for (int budget = 0; budget < 32 && Serial.available(); ++budget) {
    char c = static_cast<char>(Serial.read());
    if (c == '\r') continue;
    if (c != '\n') {
      if (inputSize < sizeof(input) - 1) input[inputSize++] = c;
      else inputOverflow = true;
      continue;
    }
    input[inputSize] = 0;
    if (!inputOverflow && validLabel(input) && online && !collecting && !csvSize) {
      strcpy(label, input); collecting = true; count = 0;
      message("[GHI] Ghi 50 mau moi trong 1 giay...");
    } else message("[LOI] Can nhan dung/ngoi/nam/di_bo/nga, cam bien OK va khong dang ghi.");
    inputSize = 0; inputOverflow = false;
  }
}
static void printCsv() {
  // Build one bounded record, then drain it asynchronously while servicing MPU.
  csvSize = snprintf(csv, sizeof(csv), "%s", label);
  csvSent = 0;
  for (int s = 0; s < Board::WINDOW_SIZE; ++s)
    for (int c = 0; c < Board::CHANNELS; ++c) {
      int n = snprintf(csv + csvSize, sizeof(csv) - csvSize, ",%.6f", samples[s][c]);
      if (n < 0 || static_cast<size_t>(n) >= sizeof(csv) - csvSize - 1) {
        csvSize = 0; message("[LOI] CSV vuot bo dem."); return;
      }
      csvSize += n;
    }
  csv[csvSize++] = '\n';
}
static void sendCsv() {
  if (!csvSize) return;
  if (!Serial) { csvSize = csvSent = 0; return; }
  int available = Serial.availableForWrite();
  if (available <= 0) return;
  size_t chunk = csvSize - csvSent;
  if (chunk > static_cast<size_t>(available)) chunk = available;
  if (chunk > 64) chunk = 64;
  csvSent += Serial.write(reinterpret_cast<const uint8_t *>(csv + csvSent), chunk);
  if (csvSent == csvSize) {
    csvSize = csvSent = 0;
    message("[XONG] San sang. CSV hop le co 301 cot.");
  }
}
void setup() {
  digitalWrite(Board::BUZZER, LOW); pinMode(Board::BUZZER, OUTPUT);
  digitalWrite(Board::LED, LOW); pinMode(Board::LED, OUTPUT);
  pinMode(Board::MPU_INT, INPUT_PULLDOWN);
  Serial.begin(115200); Serial.setTxTimeoutMs(0);
  if (!mpu.begin()) failSensor();
}
void loop() {
  uint32_t now = millis();
  if (retry && uint32_t(now - retryAt) >= Board::RETRY_MS) {
    retry = false;
    if (!mpu.begin()) failSensor();
  }
  if (!retry) {
    mpu.service(millis());
    if (mpu.state() == MPU6050_I2C::State::Failed) failSensor();
    else if (mpu.ready()) {
      if (!online) { online = true; lastData = millis(); message("[OK] MPU 50Hz, SDA8/SCL9/INT7."); }
      MPU6050Data d;
      auto result = mpu.readData(d);
      if (result == MPU6050_I2C::ReadResult::Error) failSensor();
      else if (result == MPU6050_I2C::ReadResult::NoData) {
        if (uint32_t(millis() - lastData) >= Board::SENSOR_STALE_MS) failSensor();
      } else {
        lastData = millis();
        uint32_t stamp = micros();
        if (collecting) {
          if (count && uint32_t(stamp - lastUs) > Board::MAX_SAMPLE_GAP_US) {
            collecting = false; count = 0;
            message("[LOI] Tre lay mau: huy ca cua so, khong xuat CSV gia.");
          } else {
            const float row[] = {d.ax_g, d.ay_g, d.az_g, d.gx_dps, d.gy_dps, d.gz_dps};
            memcpy(samples[count++], row, sizeof(row));
            if (count == Board::WINDOW_SIZE) { collecting = false; printCsv(); }
          }
        }
        lastUs = stamp;
      }
    }
  }
  readCommand();
  sendCsv();
  digitalWrite(Board::LED, collecting ? HIGH : (!online && (millis() % 400 < 100)));
  static uint32_t lastHelp = 0;
  if (!collecting && uint32_t(millis() - lastHelp) >= 5000) {
    lastHelp = millis();
    message("[HELP] Go dung/ngoi/nam/di_bo/nga + Enter; 50 mau @ 50Hz. Khong tu tao mau thay the.");
  }
  delay(1);
}
