# -*- coding: utf-8 -*-
"""
train_model.py
---------------------------------------------------------------------------
Trích xuất 30 đặc trưng thống kê (Bảng 3.1), chuẩn hoá (StandardScaler),
huấn luyện mạng nơ-ron MLP 30->16->8->5 (Bảng 3.3, 3.4) bằng
sklearn.neural_network.MLPClassifier, đánh giá kết quả, rồi xuất toàn bộ
trọng số + tham số chuẩn hoá ra file C header "model_weights.h" để nhúng
trực tiếp vào chương trình ESP32 (suy luận thủ công, không dùng TFLite
Micro - mục 1.2.4 / 2.2.2 của báo cáo).

Yêu cầu chạy trước: generate_synthetic_data.py (để có data/synthetic_imu_data.npz)

Chạy: python train_model.py
"""

import os
import json
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.neural_network import MLPClassifier
from sklearn.metrics import (
    accuracy_score, classification_report, confusion_matrix
)

# --------------------------------------------------------------------------
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_PATH = os.path.join(BASE_DIR, "..", "data", "synthetic_imu_data.npz")
OUT_HEADER_PY = os.path.join(BASE_DIR, "model_weights.h")
OUT_HEADER_ESP32 = os.path.join(
    BASE_DIR, "..", "esp32", "fall_detection_esp32", "model_weights.h"
)

SAMPLE_RATE_HZ = 50
WINDOW_SIZE = 50
CHANNEL_NAMES = ["ax", "ay", "az", "gx", "gy", "gz"]     # thứ tự 6 kênh
STAT_NAMES = ["mean", "std", "min", "max", "rms"]        # thứ tự 5 thống kê / kênh
N_FEATURES = len(CHANNEL_NAMES) * len(STAT_NAMES)        # 30
RANDOM_SEED = 42


# --------------------------------------------------------------------------
def extract_features(window):
    """window: mảng (WINDOW_SIZE, 6) -> vector 30 đặc trưng.

    QUAN TRỌNG: thứ tự đặc trưng đầu ra PHẢI khớp 100% với hàm
    extract_features() cài đặt trên ESP32 (fall_detection_esp32.ino):
    lặp theo từng kênh (ax, ay, az, gx, gy, gz), với mỗi kênh xuất theo
    thứ tự [mean, std, min, max, rms].
    """
    feats = []
    for ch in range(6):
        col = window[:, ch]
        mean = np.mean(col)
        std = np.std(col)
        mn = np.min(col)
        mx = np.max(col)
        rms = np.sqrt(np.mean(col ** 2))
        feats.extend([mean, std, mn, mx, rms])
    return np.array(feats, dtype=np.float64)


def build_feature_matrix(X_windows):
    return np.array([extract_features(w) for w in X_windows])


# --------------------------------------------------------------------------
def export_c_header(path, class_names, mlp, scaler, train_acc, test_acc):
    """Xuất trọng số + tham số chuẩn hoá ra file C header."""
    # scikit-learn MLPClassifier: coefs_[i] có shape (n_in, n_out) - đúng
    # chiều để nhân theo kiểu  out = in @ W + b  (hàng = input, cột = output)
    W1, W2, W3 = mlp.coefs_
    B1, B2, B3 = mlp.intercepts_

    in_dim, h1 = W1.shape
    h1b, h2 = W2.shape
    h2b, out_dim = W3.shape
    assert h1 == h1b and h2 == h2b

    mean = scaler.mean_
    std = scaler.scale_

    n_params = W1.size + B1.size + W2.size + B2.size + W3.size + B3.size

    def fmt_1d(arr):
        return ", ".join(f"{v:.8f}f" for v in arr)

    def fmt_2d(mat):
        rows = []
        for row in mat:
            rows.append("  {" + ", ".join(f"{v:.8f}f" for v in row) + "}")
        return ",\n".join(rows)

    lines = []
    lines.append("// =========================================================================")
    lines.append("// model_weights.h - TU DONG SINH BOI train_model.py - KHONG CHINH SUA TAY")
    lines.append("//")
    lines.append("// Mo hinh MLP 30 -> 16 -> 8 -> 5 (ReLU, ReLU, Softmax)")
    lines.append(f"// Do chinh xac tren tap train : {train_acc*100:.2f}%")
    lines.append(f"// Do chinh xac tren tap test  : {test_acc*100:.2f}%")
    lines.append(f"// Tong so tham so             : {n_params}")
    lines.append("// =========================================================================")
    lines.append("#ifndef MODEL_WEIGHTS_H")
    lines.append("#define MODEL_WEIGHTS_H")
    lines.append("")
    lines.append(f"#define INPUT_SIZE  {in_dim}")
    lines.append(f"#define HIDDEN1_SIZE {h1}")
    lines.append(f"#define HIDDEN2_SIZE {h2}")
    lines.append(f"#define OUTPUT_SIZE {out_dim}")
    lines.append("")
    lines.append("// Ten 5 lop, THEO DUNG THU TU voi cac neuron dau ra (bang alphabet,")
    lines.append("// giong hanh vi cua sklearn LabelEncoder da dung khi huan luyen).")
    lines.append(f"static const char* CLASS_NAMES[OUTPUT_SIZE] = {{{', '.join(chr(34)+c+chr(34) for c in class_names)}}};")
    lines.append("")
    lines.append("// Tham so chuan hoa (StandardScaler) - ap dung cho vector 30 dac trung")
    lines.append("// TRUOC khi dua vao mo hinh: x_norm[i] = (x[i] - FEATURE_MEAN[i]) / FEATURE_STD[i]")
    lines.append(f"static const float FEATURE_MEAN[INPUT_SIZE] = {{{fmt_1d(mean)}}};")
    lines.append(f"static const float FEATURE_STD[INPUT_SIZE]  = {{{fmt_1d(std)}}};")
    lines.append("")
    lines.append("// ---- Lop An 1 (Input 30 -> Hidden1 16), kich hoat ReLU ----")
    lines.append(f"static const float W1[INPUT_SIZE][HIDDEN1_SIZE] = {{\n{fmt_2d(W1)}\n}};")
    lines.append(f"static const float BIAS1[HIDDEN1_SIZE] = {{{fmt_1d(B1)}}};")
    lines.append("")
    lines.append("// ---- Lop An 2 (Hidden1 16 -> Hidden2 8), kich hoat ReLU ----")
    lines.append(f"static const float W2[HIDDEN1_SIZE][HIDDEN2_SIZE] = {{\n{fmt_2d(W2)}\n}};")
    lines.append(f"static const float BIAS2[HIDDEN2_SIZE] = {{{fmt_1d(B2)}}};")
    lines.append("")
    lines.append("// ---- Lop Dau ra (Hidden2 8 -> Output 5), kich hoat Softmax ----")
    lines.append(f"static const float W3[HIDDEN2_SIZE][OUTPUT_SIZE] = {{\n{fmt_2d(W3)}\n}};")
    lines.append(f"static const float BIAS3[OUTPUT_SIZE] = {{{fmt_1d(B3)}}};")
    lines.append("")
    lines.append("#endif // MODEL_WEIGHTS_H")

    content = "\n".join(lines) + "\n"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[OK] Da xuat: {path}  ({n_params} tham so, ~{n_params*4/1024:.2f} KB o dang float32)")


# --------------------------------------------------------------------------
def main():
    if not os.path.exists(DATA_PATH):
        raise SystemExit(
            "Khong tim thay du lieu. Hay chay 'python generate_synthetic_data.py' truoc."
        )

    npz = np.load(DATA_PATH, allow_pickle=True)
    X_windows = npz["X"]                    # (600, 50, 6)
    y_raw = npz["y"]                        # (600,) chuoi nhan
    class_names = sorted(list(npz["class_names"]))  # alphabet, khop LabelEncoder

    print(f"[INFO] So cua so du lieu: {X_windows.shape[0]}, cac lop: {class_names}")

    # 1) Trich xuat 30 dac trung / cua so
    X_feat = build_feature_matrix(X_windows)   # (600, 30)
    assert X_feat.shape[1] == N_FEATURES

    # 2) Ma hoa nhan theo thu tu alphabet (giong LabelEncoder)
    label_to_idx = {name: i for i, name in enumerate(class_names)}
    y = np.array([label_to_idx[label] for label in y_raw])

    # 3) Chia tap train/test (80/20 - Bang 3.4)
    X_train, X_test, y_train, y_test = train_test_split(
        X_feat, y, test_size=0.2, random_state=RANDOM_SEED, stratify=y
    )

    # 4) Chuan hoa (StandardScaler) - fit tren tap train
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    # 5) Huan luyen MLP (Bang 3.3, 3.4)
    mlp = MLPClassifier(
        hidden_layer_sizes=(16, 8),
        activation="relu",
        solver="adam",
        learning_rate_init=0.001,
        alpha=0.0001,
        max_iter=5000,
        random_state=RANDOM_SEED,
    )
    mlp.fit(X_train_scaled, y_train)

    # 6) Danh gia
    train_pred = mlp.predict(X_train_scaled)
    test_pred = mlp.predict(X_test_scaled)
    train_acc = accuracy_score(y_train, train_pred)
    test_acc = accuracy_score(y_test, test_pred)

    print(f"[RESULT] Do chinh xac tap train: {train_acc*100:.2f}%")
    print(f"[RESULT] Do chinh xac tap test : {test_acc*100:.2f}%")
    print("\n[RESULT] Bao cao phan loai (test set):")
    print(classification_report(y_test, test_pred, target_names=class_names, digits=3))
    print("[RESULT] Ma tran nham lan (test set):")
    print(confusion_matrix(y_test, test_pred))

    n_params = sum(w.size for w in mlp.coefs_) + sum(b.size for b in mlp.intercepts_)
    print(f"\n[INFO] Tong so tham so mo hinh: {n_params} (~{n_params*4/1024:.2f} KB o dang float32)")

    # 7) Xuat model_weights.h (2 ban: 1 trong thu muc python/, 1 trong thu muc esp32)
    export_c_header(OUT_HEADER_PY, class_names, mlp, scaler, train_acc, test_acc)
    export_c_header(OUT_HEADER_ESP32, class_names, mlp, scaler, train_acc, test_acc)

    # 8) Luu them thong tin huan luyen dang JSON de tham khao
    info = {
        "class_names": class_names,
        "n_features": N_FEATURES,
        "hidden_layers": [16, 8],
        "train_accuracy": train_acc,
        "test_accuracy": test_acc,
        "n_params": int(n_params),
        "window_size": WINDOW_SIZE,
        "sample_rate_hz": SAMPLE_RATE_HZ,
    }
    info_path = os.path.join(BASE_DIR, "training_info.json")
    with open(info_path, "w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False, indent=2)
    print(f"[OK] Da luu thong tin huan luyen: {info_path}")


if __name__ == "__main__":
    main()
