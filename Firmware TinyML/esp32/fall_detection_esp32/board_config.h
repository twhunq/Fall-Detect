#pragma once
#include <stdint.h>

// Verified against fall_detector.kicad_pcb, U1. GPIO numbers, not pad numbers.
namespace Board {
constexpr int SDA = 8;
constexpr int SCL = 9;
constexpr int MPU_INT = 7;
constexpr int TOUCH = 4;       // TTP223, active HIGH, momentary mode
constexpr int BUZZER = 5;      // Active 3 V buzzer through Q1 (S8050)
constexpr int LED = 6;         // External red LED; NOT the WS2812 on GPIO48
constexpr int BATTERY = 1;     // R4/R5 = 100k/100k, sensed at VSW, before D2
constexpr uint32_t I2C_HZ = 400000;
constexpr uint16_t I2C_TIMEOUT_MS = 5;
constexpr uint32_t RETRY_MS = 2000;
constexpr uint32_t SENSOR_STALE_MS = 100;
constexpr uint32_t MAX_SAMPLE_GAP_US = 30000;
constexpr uint32_t SAMPLE_HZ = 50;
constexpr int WINDOW_SIZE = 50;
constexpr int CHANNELS = 6;
constexpr int HOP_SIZE = 10;    // 1 s window, inference every 200 ms
constexpr float FALL_THRESHOLD = 0.70f;
constexpr uint32_t ACK_INHIBIT_MS = 10000;
constexpr uint32_t TOUCH_SETTLE_MS = 1500;
constexpr uint32_t TOUCH_DEBOUNCE_MS = 40;
constexpr uint32_t SOS_HOLD_MS = 3000;
constexpr uint32_t BATTERY_LOW_MV = 3500;
constexpr uint32_t BATTERY_RECOVER_MV = 3700;
constexpr float BATTERY_SCALE = 2.0f; // Adjust after comparison with a multimeter
}

#if defined(ARDUINO) && !defined(CONFIG_IDF_TARGET_ESP32S3)
#error "Select ESP32S3 Dev Module, not ESP32 Dev Module."
#endif
#if defined(ARDUINO) && (!ARDUINO_USB_CDC_ON_BOOT || !ARDUINO_USB_MODE)
#error "Enable USB CDC On Boot and select Hardware CDC and JTAG USB mode."
#endif
