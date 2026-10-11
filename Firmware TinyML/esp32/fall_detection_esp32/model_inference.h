#pragma once
#include <math.h>
#include "board_config.h"
#include "model_weights.h"
static_assert(INPUT_SIZE == Board::CHANNELS * 5, "Model feature count mismatch");
// Statistics are invariant to ring-buffer order; no window copy is needed.
inline void extractFeatures(const float buf[Board::WINDOW_SIZE][Board::CHANNELS],
                     float outFeatures[INPUT_SIZE]) {
  int idx = 0;
  for (int ch = 0; ch < Board::CHANNELS; ch++) {
    float sum = 0.0f;
    float sumSq = 0.0f;
    float vmin = buf[0][ch];
    float vmax = buf[0][ch];

    for (int s = 0; s < Board::WINDOW_SIZE; s++) {
      float v = buf[s][ch];
      sum += v;
      sumSq += v * v;
      if (v < vmin)
        vmin = v;
      if (v > vmax)
        vmax = v;
    }

    float mean = sum / Board::WINDOW_SIZE;

    float varSum = 0.0f;
    for (int s = 0; s < Board::WINDOW_SIZE; s++) {
      float d = buf[s][ch] - mean;
      varSum += d * d;
    }
    float std = sqrtf(varSum / Board::WINDOW_SIZE);
    float rms = sqrtf(sumSq / Board::WINDOW_SIZE);

    outFeatures[idx++] = mean;
    outFeatures[idx++] = std;
    outFeatures[idx++] = vmin;
    outFeatures[idx++] = vmax;
    outFeatures[idx++] = rms;
  }
}

// ==========================================================================
// Chuan hoa dac trung: x_norm = (x - FEATURE_MEAN) / FEATURE_STD
// ==========================================================================
inline void normalizeFeatures(float features[INPUT_SIZE]) {
  for (int i = 0; i < INPUT_SIZE; i++) {
    float std = FEATURE_STD[i];
    if (std < 1e-8f)
      std = 1e-8f; // tranh chia cho 0
    features[i] = (features[i] - FEATURE_MEAN[i]) / std;
  }
}

// ==========================================================================
// Suy luan thu cong qua 3 lop mang no-ron (nhan ma tran + ReLU + Softmax)
// ==========================================================================
inline void reluInplace(float *v, int n) {
  for (int i = 0; i < n; i++) {
    if (v[i] < 0.0f)
      v[i] = 0.0f;
  }
}

inline void softmaxInplace(float *v, int n) {
  float maxVal = v[0];
  for (int i = 1; i < n; i++)
    if (v[i] > maxVal)
      maxVal = v[i];

  float sum = 0.0f;
  for (int i = 0; i < n; i++) {
    v[i] = expf(v[i] - maxVal);
    sum += v[i];
  }
  if (sum < 1e-12f)
    sum = 1e-12f;
  for (int i = 0; i < n; i++)
    v[i] /= sum;
}

// Tra ve chi so lop du doan (argmax); ghi do tin cay vao outConfidence.
inline int runInference(const float features[INPUT_SIZE], float *outConfidence) {
  *outConfidence = 0.0f;
  for (int i = 0; i < INPUT_SIZE; ++i)
    if (!isfinite(features[i])) return -1;
  float h1[HIDDEN1_SIZE];
  float h2[HIDDEN2_SIZE];
  float out[OUTPUT_SIZE];

  // Lop an 1: h1 = ReLU(features . W1 + BIAS1)
  for (int j = 0; j < HIDDEN1_SIZE; j++) {
    float acc = BIAS1[j];
    for (int i = 0; i < INPUT_SIZE; i++) {
      acc += features[i] * W1[i][j];
    }
    h1[j] = acc;
  }
  reluInplace(h1, HIDDEN1_SIZE);

  // Lop an 2: h2 = ReLU(h1 . W2 + BIAS2)
  for (int j = 0; j < HIDDEN2_SIZE; j++) {
    float acc = BIAS2[j];
    for (int i = 0; i < HIDDEN1_SIZE; i++) {
      acc += h1[i] * W2[i][j];
    }
    h2[j] = acc;
  }
  reluInplace(h2, HIDDEN2_SIZE);

  // Lop dau ra: out = Softmax(h2 . W3 + BIAS3)
  for (int j = 0; j < OUTPUT_SIZE; j++) {
    float acc = BIAS3[j];
    for (int i = 0; i < HIDDEN2_SIZE; i++) {
      acc += h2[i] * W3[i][j];
    }
    out[j] = acc;
  }
  for (int i = 0; i < OUTPUT_SIZE; ++i)
    if (!isfinite(out[i])) return -1;
  softmaxInplace(out, OUTPUT_SIZE);

  int bestIdx = 0;
  float bestVal = out[0];
  for (int i = 1; i < OUTPUT_SIZE; i++) {
    if (out[i] > bestVal) {
      bestVal = out[i];
      bestIdx = i;
    }
  }
  *outConfidence = bestVal;
  return bestIdx;
}

