# -*- coding: utf-8 -*-
"""
generate_synthetic_data.py
---------------------------------------------------------------------------
Sinh dữ liệu MÔ PHỎNG (synthetic) cho bài toán phân loại 5 trạng thái vận
động: dung (đứng), ngoi (ngồi), nam (nằm), di_bo (đi bộ), nga (ngã),
phục vụ huấn luyện mô hình TinyML (Chương 3, mục 3.3 của báo cáo).

- Tần số lấy mẫu mô phỏng: 50Hz
- Độ dài 1 cửa sổ: 1 giây = 50 mẫu
- Mỗi lớp: 120 cửa sổ  -> tổng cộng 600 cửa sổ (cân bằng hoàn toàn)
- Mỗi mẫu gồm 6 kênh: ax, ay, az (đơn vị g), gx, gy, gz (đơn vị độ/giây)

Dữ liệu được sinh dựa trên đặc trưng động học hợp lý của từng trạng thái,
bám sát các giá trị trung bình mô tả tại Bảng 3.2 của báo cáo, ví dụ:
- Đứng: az ~ 1g ổn định, dao động rất nhỏ.
- Ngồi: az ~ 0.97g, dao động nhẹ nhàng hơn đứng một chút.
- Nằm: trọng lực dồn sang trục X (ax ~ 0.95g), az rất thấp (~0.10g).
- Đi bộ: az ~ 1.02g nhưng dao động tuần hoàn theo bước chân (gx_rms cao).
- Ngã: có giai đoạn rơi tự do (gia tốc gần 0) rồi va đập (đỉnh gia tốc
  lớn > 2g) kèm theo con quay hồi chuyển tăng vọt ở cả 3 trục (>58 độ/giây).

Kết quả được lưu ra file CSV (mỗi dòng là 1 cửa sổ dữ liệu thô, được nén
lại thành chuỗi để tái sử dụng) và một file .npz chứa mảng numpy để
train_model.py sử dụng trực tiếp.

Chạy: python generate_synthetic_data.py
"""

import numpy as np
import pandas as pd
import os

# --------------------------------------------------------------------------
# Cấu hình chung
# --------------------------------------------------------------------------
SAMPLE_RATE_HZ = 50          # tần số lấy mẫu (Hz)
WINDOW_SIZE = 50             # số mẫu / cửa sổ (1 giây)
WINDOWS_PER_CLASS = 120      # số cửa sổ mỗi lớp -> 120*5 = 600 cửa sổ
RANDOM_SEED = 42

# Thứ tự nhãn lớp (SẮP XẾP THEO ALPHABET giống hành vi mặc định của
# sklearn.preprocessing.LabelEncoder) -- PHẢI đồng nhất giữa
# train_model.py và mã nguồn ESP32 (model_weights.h -> CLASS_NAMES).
CLASS_NAMES = ["di_bo", "dung", "nam", "nga", "ngoi"]

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
os.makedirs(OUT_DIR, exist_ok=True)

rng = np.random.default_rng(RANDOM_SEED)


def _noise(shape, sigma):
    return rng.normal(0.0, sigma, size=shape)


def gen_dung(n_windows):
    """Đứng: az ~ 1g ổn định, dao động rất nhỏ ở cả 3 trục."""
    out = np.zeros((n_windows, WINDOW_SIZE, 6))
    for i in range(n_windows):
        ax = 0.013 + _noise(WINDOW_SIZE, 0.02)
        ay = 0.000 + _noise(WINDOW_SIZE, 0.02)
        az = 1.000 + _noise(WINDOW_SIZE, 0.02)
        gx = _noise(WINDOW_SIZE, 2.0)
        gy = _noise(WINDOW_SIZE, 2.0)
        gz = _noise(WINDOW_SIZE, 2.0)
        out[i] = np.stack([ax, ay, az, gx, gy, gz], axis=1)
    return out


def gen_ngoi(n_windows):
    """Ngồi: az ~ 0.97g, dao động nhẹ hơn đứng, hơi nghiêng."""
    out = np.zeros((n_windows, WINDOW_SIZE, 6))
    for i in range(n_windows):
        ax = 0.150 + _noise(WINDOW_SIZE, 0.03)
        ay = 0.050 + _noise(WINDOW_SIZE, 0.03)
        az = 0.970 + _noise(WINDOW_SIZE, 0.03)
        gx = _noise(WINDOW_SIZE, 1.5)
        gy = _noise(WINDOW_SIZE, 1.5)
        gz = _noise(WINDOW_SIZE, 1.5)
        out[i] = np.stack([ax, ay, az, gx, gy, gz], axis=1)
    return out


def gen_nam(n_windows):
    """Nằm: trọng lực dồn sang trục X, az rất thấp."""
    out = np.zeros((n_windows, WINDOW_SIZE, 6))
    for i in range(n_windows):
        ax = 0.950 + _noise(WINDOW_SIZE, 0.03)
        ay = 0.050 + _noise(WINDOW_SIZE, 0.03)
        az = 0.100 + _noise(WINDOW_SIZE, 0.03)
        gx = _noise(WINDOW_SIZE, 1.5)
        gy = _noise(WINDOW_SIZE, 1.5)
        gz = _noise(WINDOW_SIZE, 1.5)
        out[i] = np.stack([ax, ay, az, gx, gy, gz], axis=1)
    return out


def gen_di_bo(n_windows):
    """Đi bộ: az dao động tuần hoàn quanh 1.02g, gx_rms cao do nhịp bước."""
    out = np.zeros((n_windows, WINDOW_SIZE, 6))
    t = np.arange(WINDOW_SIZE) / SAMPLE_RATE_HZ
    for i in range(n_windows):
        step_freq = rng.uniform(1.8, 2.2)  # bước/giây
        phase = rng.uniform(0, 2 * np.pi)
        ax = 0.018 + 0.05 * np.sin(2 * np.pi * step_freq * t + phase) + _noise(WINDOW_SIZE, 0.03)
        ay = -0.005 + 0.04 * np.cos(2 * np.pi * step_freq * t + phase) + _noise(WINDOW_SIZE, 0.03)
        az = 1.019 + 0.15 * np.sin(2 * np.pi * step_freq * t) + _noise(WINDOW_SIZE, 0.05)
        gx = 29.69 * np.sin(2 * np.pi * step_freq * t + phase) + _noise(WINDOW_SIZE, 4.0)
        gy = 22.46 * np.cos(2 * np.pi * step_freq * t + phase) + _noise(WINDOW_SIZE, 4.0)
        gz = 5.98 * np.sin(2 * np.pi * step_freq * t * 2) + _noise(WINDOW_SIZE, 2.0)
        out[i] = np.stack([ax, ay, az, gx, gy, gz], axis=1)
    return out


def gen_nga(n_windows):
    """Ngã: rơi tự do (gia tốc ~0) -> va đập (đỉnh > 2g) -> con quay hồi
    chuyển tăng vọt (>58 độ/giây trên cả 3 trục) do xoay mất kiểm soát."""
    out = np.zeros((n_windows, WINDOW_SIZE, 6))
    for i in range(n_windows):
        impact_idx = rng.integers(20, 32)  # va đập xảy ra giữa cửa sổ
        ax = _noise(WINDOW_SIZE, 0.05)
        ay = _noise(WINDOW_SIZE, 0.05)
        az = _noise(WINDOW_SIZE, 0.05)

        # Giai đoạn trước va đập: gần như rơi tự do (gia tốc tổng hợp ~0)
        for k in range(0, impact_idx):
            decay = 1.0 - (k / max(impact_idx, 1))
            az[k] += 0.055 * decay

        # Giai đoạn va đập: xung gia tốc lớn (>2g) suy giảm dần
        impact_len = 6
        for k in range(impact_idx, min(impact_idx + impact_len, WINDOW_SIZE)):
            j = k - impact_idx
            impulse = 2.5 * np.exp(-j / 2.0)
            az[k] += impulse
            ax[k] += 0.4 * impulse * rng.uniform(-1, 1)

        # Sau va đập: nằm bất động trên sàn
        for k in range(impact_idx + impact_len, WINDOW_SIZE):
            az[k] += 0.055

        # Con quay hồi chuyển: tăng vọt quanh thời điểm ngã do xoay người
        gx = np.zeros(WINDOW_SIZE)
        gy = np.zeros(WINDOW_SIZE)
        gz = np.zeros(WINDOW_SIZE)
        spin_len = 10
        for k in range(impact_idx, min(impact_idx + spin_len, WINDOW_SIZE)):
            j = k - impact_idx
            envelope = np.sin(np.pi * j / spin_len)
            gx[k] = 62.07 * envelope * rng.uniform(0.8, 1.2)
            gy[k] = 61.73 * envelope * rng.uniform(0.8, 1.2) * rng.choice([-1, 1])
            gz[k] = 58.78 * envelope * rng.uniform(0.8, 1.2) * rng.choice([-1, 1])
        gx += _noise(WINDOW_SIZE, 3.0)
        gy += _noise(WINDOW_SIZE, 3.0)
        gz += _noise(WINDOW_SIZE, 3.0)

        out[i] = np.stack([ax, ay, az, gx, gy, gz], axis=1)
    return out


GENERATORS = {
    "di_bo": gen_di_bo,
    "dung": gen_dung,
    "nam": gen_nam,
    "nga": gen_nga,
    "ngoi": gen_ngoi,
}


def main():
    all_windows = []
    all_labels = []
    for label in CLASS_NAMES:
        windows = GENERATORS[label](WINDOWS_PER_CLASS)
        all_windows.append(windows)
        all_labels.extend([label] * WINDOWS_PER_CLASS)

    X = np.concatenate(all_windows, axis=0)      # (600, 50, 6)
    y = np.array(all_labels)                     # (600,)

    # Xáo trộn dữ liệu
    perm = rng.permutation(len(y))
    X = X[perm]
    y = y[perm]

    npz_path = os.path.join(OUT_DIR, "synthetic_imu_data.npz")
    np.savez_compressed(npz_path, X=X, y=y, class_names=np.array(CLASS_NAMES))
    print(f"[OK] Da luu du lieu dang numpy: {npz_path}  (X: {X.shape}, y: {y.shape})")

    # Xuất thêm bản CSV "phẳng" (mỗi dòng 1 mẫu, kèm window_id + label) để
    # dễ kiểm tra / mở bằng Excel.
    rows = []
    for w_idx in range(X.shape[0]):
        for s_idx in range(WINDOW_SIZE):
            ax, ay, az, gx, gy, gz = X[w_idx, s_idx]
            rows.append({
                "window_id": w_idx,
                "sample_id": s_idx,
                "label": y[w_idx],
                "ax_g": ax, "ay_g": ay, "az_g": az,
                "gx_dps": gx, "gy_dps": gy, "gz_dps": gz,
            })
    df = pd.DataFrame(rows)
    csv_path = os.path.join(OUT_DIR, "synthetic_imu_data.csv")
    df.to_csv(csv_path, index=False, encoding="utf-8-sig")
    print(f"[OK] Da luu du lieu dang CSV: {csv_path}  ({len(df)} dong)")

    # Thống kê nhanh số cửa sổ / lớp
    unique, counts = np.unique(y, return_counts=True)
    print("[INFO] Phan bo so cua so theo lop:")
    for u, c in zip(unique, counts):
        print(f"    {u:8s}: {c}")


if __name__ == "__main__":
    main()
