# Hệ thống IoT Phát hiện & Cảnh báo Té ngã (`Fall_detect`)

Hệ thống giám sát và cảnh báo té ngã đa tầng cho người cao tuổi, kết hợp hai nhánh phần cứng AI tại biên (**Edge AI**) và nền tảng **Cloud Realtime**:

1. **Thiết bị đeo TinyML (`firmware/wearable/`)**: Vi điều khiển **ESP32-S3 Super Mini** + cảm biến quán tính 6 trục **MPU6050**, chạy mô hình mạng nơ-ron **MLP (30 → 16 → 8 → 5)** kết hợp xác nhận động học sau va đập, cảnh báo còi/LED tại chỗ, cấu hình qua Web Portal nội bộ, đồng bộ **Firebase Realtime Database** và gửi tin khẩn cấp qua **Telegram / Gmail**.
2. **Thiết bị Camera AI (`firmware/camera-k230/`)**: Camera **CanMV K230** chạy mô hình thị giác **YOLOv5n** + bộ theo dõi đa đối tượng IoU + bỏ phiếu M-trong-N, kết nối UART tốc độ cao (`921600 baud`) sang **ESP32-S3 DevKitC-1 N16R8** để phát cảnh báo **BLE 5.0** (xác thực `HMAC-SHA256`), đẩy ảnh bằng chứng lên Relay và phát luồng video trực tiếp **MJPEG**.
3. **Cloud & Web Dashboard (`cloud/`)**: Trang giám sát thời gian thực và phân quyền người dùng trên **Firebase Hosting & Realtime Database**.
4. **Ứng dụng di động "Báo Ngã IoT" (`mobile/`)**: Flutter đa nền tảng (Android `.apk`, iOS `.ipa` chưa ký cài bằng **Sideloadly**), nghe song song 4 đường cảnh báo (UDP LAN, BLE camera, Firebase SSE, Web Portal nội mạng), hú còi/rung/màn hình báo động đỏ khi đường nhanh nhất tới, khử trùng lặp và hợp nhất "Vòng đeo + Camera AI" trong 30 giây.
5. **Phần cứng PCB (`hardware/pcb/`)**: Thiết kế mạch nguyên lý, PCB 2 lớp `60 × 50 mm` (KiCad 10), mô hình 3D `.step`, BOM và file Gerber sẵn sàng gia công.

---

## Cấu trúc thư mục dự án

```text
Fall_detect/
├── firmware/
│   ├── wearable/                  # Thiết bị đeo ESP32-S3 Super Mini + TinyML
│   │   ├── src/
│   │   │   ├── fall_detection_esp32/  # Firmware chính (C++17, header-only)
│   │   │   └── data_collection/       # Sketch thu thập dữ liệu IMU 50Hz CSV
│   │   ├── ml/                    # Sinh dữ liệu mô phỏng & huấn luyện MLP
│   │   │   ├── data/              # Tập dữ liệu huấn luyện (.npz, .csv)
│   │   │   ├── generate_synthetic_data.py
│   │   │   ├── train_model.py
│   │   │   ├── training_info.json
│   │   │   └── requirements.txt
│   │   ├── scripts/               # Công cụ build, nạp firmware & Serial Monitor
│   │   │   ├── flash.py
│   │   │   ├── serial_monitor.py
│   │   │   ├── flash.bat
│   │   │   └── monitor.bat
│   │   ├── tests/                 # Bộ kiểm thử đơn vị C++17 & Python chạy trên host
│   │   └── README.md
│   │
│   └── camera-k230/               # Thiết bị giám sát Camera K230 + ESP32-S3 Bridge
│       ├── include/               # Các module header BLE, HMAC-SHA256, Relay, Telegram
│       ├── src/
│       │   └── main.cpp           # Chương trình cầu nối ESP32-S3 (PlatformIO)
│       ├── k230/
│       │   └── falldown_detect.py # Chương trình thị giác AI trên CanMV K230
│       ├── scripts/
│       │   └── flash_bridge.bat   # Script build & nạp nhanh ESP32-S3 Bridge
│       ├── platformio.ini
│       └── README.md
│
├── cloud/                         # Firebase Hosting & Realtime Database
│   ├── public/                    # Giao diện Web Dashboard (index.html, config.js)
│   ├── database.rules.json        # Luật phân quyền bảo mật RTDB
│   ├── access.example.json        # Mẫu cấu hình cây phân quyền /access
│   ├── firebase.json
│   └── .firebaserc
│
├── mobile/                        # App Flutter "Báo Ngã IoT" (Android APK + iOS IPA Sideloadly)
│   ├── lib/                       # config, core/ (giao thức, hợp nhất cảnh báo), services/, platform/, state/, ui/
│   ├── test/                      # Unit test giao thức/hợp nhất + widget test
│   ├── scripts/                   # flutter_env.ps1, setup_local_sdk.ps1, clean_cache.ps1 (mọi thứ trên D:\dev-tools)
│   └── tools/                     # generate_qr.py (mã QR ghép camera), make_alarm_sound.py
│
├── .github/workflows/build-mobile.yml  # CI: analyze + test + APK (Ubuntu) & IPA chưa ký (macOS)
│
├── hardware/
│   └── pcb/                       # Thiết kế KiCad 10 Schematic, PCB, Gerber, BOM & 3D STEP
│
├── docs/                          # Tài liệu kiểm thử phần cứng, hướng dẫn app & báo cáo
│   ├── huong-dan-app-mobile.md
│   ├── validation.md
│   └── reports/
│
└── .gitignore
```

---

## Hướng dẫn nhanh (Quickstart)

### 1. Thiết bị đeo TinyML (`firmware/wearable/`)
```powershell
cd firmware/wearable

# Chạy toàn bộ kiểm thử đơn vị C++17 + Python trên máy tính:
python tests/run_tests.py

# Biên dịch kiểm tra cả 2 sketch (Arduino-ESP32 core 3.3.8):
python scripts/flash.py --build-only
python scripts/flash.py --build-only --sketch data_collection

# Biên dịch & nạp vào mạch ESP32-S3 Super Mini:
python scripts/flash.py --port COM7
python scripts/serial_monitor.py --port COM7
```
Xem chi tiết cấu hình `secrets.h`, hiệu chỉnh cảm biến và Web Portal tại [`firmware/wearable/README.md`](firmware/wearable/README.md).

### 2. Thiết bị Camera K230 + Cầu nối ESP32-S3 (`firmware/camera-k230/`)
```powershell
cd firmware/camera-k230

# Biên dịch firmware cầu nối ESP32-S3 bằng PlatformIO:
pio run -e camera_bridge

# Biên dịch & nạp qua cổng UART trên DevKitC-1:
scripts\flash_bridge.bat COM3
```
Chép [`firmware/camera-k230/k230/falldown_detect.py`](firmware/camera-k230/k230/falldown_detect.py) vào thẻ nhớ CanMV K230 theo hướng dẫn tại [`firmware/camera-k230/README.md`](firmware/camera-k230/README.md).

### 3. Triển khai Cloud Dashboard (`cloud/`)
```powershell
cd cloud
npx firebase-tools login
npx firebase-tools deploy
```

### 4. Mạch in PCB (`hardware/pcb/`)
Mở [`hardware/pcb/fall_detector.kicad_pro`](hardware/pcb/fall_detector.kicad_pro) bằng **KiCad 10** hoặc dùng trực tiếp gói sản xuất [`hardware/pcb/production/fall_detector_gerber.zip`](hardware/pcb/production/fall_detector_gerber.zip). Chi tiết sơ đồ chân và linh kiện xem tại [`hardware/pcb/README.md`](hardware/pcb/README.md).

### 5. Ứng dụng di động "Báo Ngã IoT" (`mobile/`)
Mọi SDK và cache nằm trên `D:\dev-tools\` (không ghi vào ổ `C:`):
```powershell
. .\mobile\scripts\flutter_env.ps1      # Lần đầu tự tải Flutter stable về D:\dev-tools\flutter
cd mobile
flutter pub get
flutter analyze
flutter test

# Tự đóng gói APK trên Windows (tùy chọn): cài JDK 17 + Android SDK vào D:\dev-tools
powershell -ExecutionPolicy Bypass -File scripts\setup_local_sdk.ps1
flutter build apk --release --split-per-abi

# Dọn cache/tạm sau khi làm xong (D:\dev-tools\cache, D:\dev-tools\temp, build/, .dart_tool/)
powershell -ExecutionPolicy Bypass -File scripts\clean_cache.ps1
```
- **Android**: tải `app-arm64-v8a-release.apk` (hoặc `app-release.apk`) từ artifact CI `baonga-android`, cài trực tiếp. App không xin quyền SMS/gọi điện; nút SOS mở trình quay số (`tel:`).
- **iOS**: tải `baonga-ios-unsigned.ipa` từ artifact CI `baonga-ios-unsigned`, kéo thả vào **Sideloadly** và ký bằng Apple ID miễn phí (hiệu lực 7 ngày). Ứng dụng không dùng entitlement trả phí (Push, App Groups, Multicast); cảnh báo UDP tới iPhone bằng unicast.
- **Mã QR ghép camera**: `python mobile/tools/generate_qr.py --mac <MAC cầu nối> --out mobile/qr` (MASTER_KEY qua `--master` hoặc biến `BAONGA_MASTER_KEY`; lấy MAC bằng lệnh `WHOAMI` trên Serial của cầu nối).
- Chi tiết cài đặt từng bước (cấp quyền nền Android, Sideloadly + tự gia hạn 7 ngày trên iOS, kiểm tra độ trễ): [`docs/huong-dan-app-mobile.md`](docs/huong-dan-app-mobile.md).

---

## Đường truyền cảnh báo "Thời gian vàng" (5 lớp)

| Lớp | Cơ chế | Vị trí |
|---|---|---|
| 1 | **UDP LAN Emergency Burst**: `BAONGA|1|<seq>|<device_id>|<FALL\|INACTIVE\|RESUMED>|<metric>|<ip>` tới cổng `4210`, 3 gói cách 20 ms (broadcast + unicast tới 4 điện thoại gần nhất đã gọi Web Portal) | `firmware/wearable/.../lan_alert_*.h`, `firmware/camera-k230/include/lan_alert_udp.h` |
| 2 | **BLE không chặn**: NOTIFY đầu tại 0 ms, 2 lần lặp mỗi 400 ms trong `BleAlert::loop()` (bỏ `delay(400)`) | `firmware/camera-k230/include/ble_alert.h` |
| 3 | **Thiết lập kết nối trước** (*connection pre-warming*) khi va đập ≥ 2 g làm phát sinh sự kiện nghi ngã: tắt Modem Sleep ~10 s, dựng sẵn phiên TLS Firebase; sự kiện bị loại bỏ thì không phát gì | `notifier.h` (`boost`), `cloud_sync.h` (`prewarm`) |
| 4 | **Zero-Wait & Fast-Flush**: cập nhật trạng thái ngay, đánh thức tác vụ bằng task notification, `TCP_NODELAY`; đẩy `alarm` lên Firebase trên phiên TLS dựng sẵn (keep-alive) rồi nhường `TlsGate` cho Telegram → Gmail (luôn tối đa 1 phiên TLS) | `fall_detection_esp32.ino`, `cloud_sync.h` |
| 5 | **Đua đa kênh & hợp nhất**: app nghe UDP + BLE + Firebase SSE + Web Portal; gói tới trước kích hoạt báo động, bản lặp bị khử; vòng đeo + camera trong 30 s → "ĐA NGUỒN XÁC NHẬN" | `mobile/lib/core/fusion/` |

---

## Đóng góp và giấy phép

- Dự án mã nguồn mở, hoan nghênh mọi người cùng phát triển: mở **issue** để báo lỗi hoặc đề xuất, gửi **pull request** cho bản sửa. Hướng đang cần: tối ưu mô hình và năng lượng, đưa lõi phát hiện lên kính AI, đồng hồ, quần áo thông minh; góp dữ liệu và kịch bản thử.
- Không đưa thông tin bí mật vào commit: dùng các tệp mẫu `secrets.example.h`, `device_secrets.example.h`, `k230_wifi.example.json` (bản thật đã gitignore).
- Giấy phép: [MIT](LICENSE) © 2026 Marine (Tuấn Hưng).
