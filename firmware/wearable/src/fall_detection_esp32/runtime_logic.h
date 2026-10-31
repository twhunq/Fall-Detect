#pragma once
#include <stdint.h>
#include "board_config.h"
#include "detection_config.h"
#include "imu_filter.h"

// Unsigned elapsed-time arithmetic remains correct across millis()/micros() wrap.
class SampleWindow {
 public:
  float data[Board::WINDOW_SIZE][Board::CHANNELS] = {};
  void clear() { next_ = count_ = hop_ = 0; haveTime_ = false; }
  bool gapBefore(uint32_t nowUs) const {
    return haveTime_ && uint32_t(nowUs - lastUs_) > Board::MAX_SAMPLE_GAP_US;
  }
  bool push(const float sample[Board::CHANNELS], uint32_t nowUs, bool &gap) {
    gap = gapBefore(nowUs);
    if (gap) clear();
    lastUs_ = nowUs;
    haveTime_ = true;
    for (int c = 0; c < Board::CHANNELS; ++c) data[next_][c] = sample[c];
    next_ = (next_ + 1) % Board::WINDOW_SIZE;
    if (count_ < Board::WINDOW_SIZE) {
      ++count_;
      return count_ == Board::WINDOW_SIZE;
    }
    if (++hop_ < Board::HOP_SIZE) return false;
    hop_ = 0;
    return true;
  }
 private:
  int next_ = 0, count_ = 0, hop_ = 0;
  uint32_t lastUs_ = 0;
  bool haveTime_ = false;
};

class AlertController {
 public:
  bool active = false;
  uint32_t started = 0;
  void acknowledge(uint32_t now) {
    active = false;
    inhibited_ = true;
    acknowledged_ = now;
  }
  // A fall already confirmed by FallDetector; latches until acknowledged.
  bool trigger(uint32_t now) {
    if (inhibited_ && uint32_t(now - acknowledged_) >= Board::ACK_INHIBIT_MS)
      inhibited_ = false;
    if (inhibited_ || active) return false;
    active = true;
    started = now;
    return true;
  }
 private:
  bool inhibited_ = false;
  uint32_t acknowledged_ = 0;
};

// N short taps within a window (used to enter calibration when no alarm).
class TapCounter {
 public:
  void clear() { count_ = 0; }
  bool tap(uint32_t now) {
    if (count_ == 0 || uint32_t(now - first_) > Detect::CAL_TAP_WINDOW_MS) { count_ = 0; first_ = now; }
    if (++count_ < Detect::CAL_TAPS) return false;
    count_ = 0;
    return true;
  }
 private:
  uint8_t count_ = 0;
  uint32_t first_ = 0;
};

enum class TouchEvent { None, Tap, Hold };
class TouchInput {
 public:
  TouchEvent update(bool raw, uint32_t now) {
    if (raw != raw_) { raw_ = raw; changed_ = now; }
    if (!settled_ && now >= Board::TOUCH_SETTLE_MS) settled_ = true;
    if (!settled_ || uint32_t(now - changed_) < Board::TOUCH_DEBOUNCE_MS)
      return TouchEvent::None;
    // Require a released sensor after power-on before accepting a touch.
    if (!armed_) { if (!raw_) armed_ = true; return TouchEvent::None; }
    if (stable_ != raw_) {
      stable_ = raw_;
      if (stable_) { pressed_ = now; held_ = false; }
      else if (!held_) return TouchEvent::Tap;
    }
    if (stable_ && !held_ && uint32_t(now - pressed_) >= Board::POWER_HOLD_MS) {
      held_ = true;
      return TouchEvent::Hold;
    }
    return TouchEvent::None;
  }
 private:
  bool raw_ = false, stable_ = false, held_ = false, armed_ = false, settled_ = false;
  uint32_t changed_ = 0, pressed_ = 0;
};

// "Bất động": no body movement for longer than the limit set on the web page.
// One alert per still period; when the wearer moves (or touches the device,
// which needs a conscious wearer) after an alert, Resumed is reported once.
class InactivityMonitor {
 public:
  enum class Event : uint8_t { None, Alert, Resumed };

  // New count from `now` (boot, sensor back online): time without sensor data
  // is not claimed as stillness. An alert already sent stays sent.
  void restart(uint32_t now) {
    lastMove_ = now;
    run_ = 0;
    started_ = true;
    motion_.reset();
  }
  // Filtered sample; limitMs 0 = no alert (switched off, or an alarm is active).
  Event update(const float s[Board::CHANNELS], uint32_t now, uint32_t limitMs) {
    if (!started_) restart(now);
    motion_.update(s);
    const bool moving = motion_.acc >= Detect::MOVE_ACC_G || motion_.gyro >= Detect::MOVE_GYRO_DPS;
    run_ = moving ? (run_ < Detect::MOVE_MIN_SAMPLES ? run_ + 1 : run_) : 0;
    if (run_ >= Detect::MOVE_MIN_SAMPLES) return moved(now);
    if (!alerted_ && limitMs && uint32_t(now - lastMove_) >= limitMs) {
      alerted_ = true;
      return Event::Alert;
    }
    return Event::None;
  }
  Event touched(uint32_t now) { return started_ ? moved(now) : Event::None; }

  bool alerted() const { return alerted_; }
  uint32_t stillMs(uint32_t now) const { return started_ ? uint32_t(now - lastMove_) : 0; }
  // Length of the still period that just ended with Resumed.
  uint32_t endedStillMs() const { return endedStill_; }

 private:
  MotionLevel motion_;
  uint32_t lastMove_ = 0, endedStill_ = 0;
  int run_ = 0;
  bool started_ = false, alerted_ = false;

  Event moved(uint32_t now) {
    const uint32_t still = now - lastMove_;
    lastMove_ = now;
    if (!alerted_) return Event::None;
    alerted_ = false;
    endedStill_ = still;
    return Event::Resumed;
  }
};
