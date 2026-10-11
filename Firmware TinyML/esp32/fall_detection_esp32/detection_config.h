#pragma once
#include <stdint.h>

// Fall confirmation, noise filter and calibration tuning. Units: g, deg/s, ms.
// Values are starting points; tune them with the [FALL?] log lines on real wear.
namespace Detect {
// Candidate: an impact peak on the filtered acceleration magnitude.
constexpr float IMPACT_G = 2.0f;
// Supporting evidence (any one): free fall shortly before impact, a fast body
// rotation around impact, or the ML model voting "nga" right after impact.
constexpr float FREEFALL_G = 0.6f;
constexpr uint32_t FREEFALL_LOOKBACK_MS = 1000;
constexpr float ROTATION_DPS = 120.0f;
constexpr float ROTATION_PEAK_DECAY = 0.95f; // per sample, ~0.3 s half-life at 50 Hz
constexpr uint32_t ML_VOTE_MS = 1500;
// Confirmation: after the bounce/settle period the wearer must stay mostly
// still in a posture clearly different from the one before the impact.
constexpr uint32_t SETTLE_MS = 1000;
constexpr uint32_t OBSERVE_MS = 2000;
constexpr float STILL_ACC_G = 0.20f;
constexpr float STILL_GYRO_DPS = 30.0f;
constexpr float STILL_FRACTION = 0.80f;
constexpr float POSTURE_CHANGE_DEG = 45.0f;
// Reference "before" posture: slow average of gravity while not moving hard.
constexpr float REF_ALPHA = 0.02f;
constexpr float REF_ACC_TOL_G = 0.15f;

// Noise filter: slow gyro zero-rate tracking while the device is motionless.
constexpr float BIAS_STILL_DPS = 3.0f;
constexpr float BIAS_STILL_ACC_G = 0.05f;
constexpr int BIAS_STILL_SAMPLES = 100; // 2 s at 50 Hz
constexpr float BIAS_TRACK_ALPHA = 0.01f;

// Calibration: wear the device, stand upright and keep still.
constexpr uint32_t CAL_SETTLE_MS = 2000;
constexpr int CAL_SAMPLES = 150; // 3 s at 50 Hz
constexpr uint32_t CAL_TIMEOUT_MS = 20000;
constexpr float CAL_MAX_ACC_STD_G = 0.04f;
constexpr float CAL_MAX_GYRO_STD_DPS = 3.0f;
constexpr float CAL_MAX_GYRO_BIAS_DPS = 20.0f;
constexpr float CAL_MIN_G = 0.85f;
constexpr float CAL_MAX_G = 1.15f;
constexpr uint8_t CAL_TAPS = 3;
constexpr uint32_t CAL_TAP_WINDOW_MS = 1500;

// Movement measure (MotionLevel): distance of each sample from its own ~0.5 s
// average, so accelerometer offset, gyro bias and posture do not count.
constexpr float MOTION_AVG_ALPHA = 0.04f;

// Inactivity ("bất động"): the timer restarts on real body movement only.
// Breathing, heartbeat and sensor noise stay far below these levels.
constexpr float MOVE_ACC_G = 0.06f;
constexpr float MOVE_GYRO_DPS = 12.0f;
constexpr int MOVE_MIN_SAMPLES = 3; // 60 ms in a row
}
