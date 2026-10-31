# Thiết bị giám sát té ngã: Camera K230 + Cầu nối ESP32-S3

## Thành phần
- **Camera K230 (CanMV)** chạy [`k230/falldown_detect.py`](k230/falldown_detect.py): nhận diện té ngã bằng YOLOv5n, theo dõi đối tượng bằng IoU, bỏ phiếu M-trong-N, phát luồng video trực tiếp MJPEG trong mạng LAN và đẩy ảnh bằng chứng lên Relay.
- **ESP32-S3 DevKitC-1 N16R8** (`src/main.cpp` + `include/`): làm cầu nối UART tốc độ cao sang **BLE 5.0**, **Relay Server** và **Telegram**, quảng bá BLE có định danh MAC, xác thực `HMAC-SHA256` qua mã QR và nhận cấu hình từ ứng dụng di động.

## Cấu trúc thư mục
```text
firmware/camera-k230/
├── platformio.ini                   # Cấu hình PlatformIO (ESP32-S3 N16R8, espressif32@6.7.0)
├── src/
│   └── main.cpp                     # Vòng lặp chính cầu nối UART <-> BLE / Relay / Telegram
├── include/
│   ├── ble_alert.h                  # BLE Server, phát cảnh báo & nhận cấu hình
│   ├── device_config.h              # Lưu/nạp cấu hình Wi-Fi, Telegram, Home ID, Relay trong NVS
│   ├── device_identity.h            # Định danh MAC efuse & xác thực HMAC-SHA256
│   ├── relay_client.h               # Ký gói tin cảnh báo & xin phiếu tải ảnh bằng chứng
│   ├── telegram_alert.h             # Kênh dự phòng gửi cảnh báo trực tiếp qua Telegram Bot API
│   └── device_secrets.example.h     # Mẫu cấu hình bí mật (chép thành device_secrets.h, đã gitignore)
├── k230/
│   └── falldown_detect.py           # Chương trình MicroPython chạy trên CanMV K230
└── scripts/
    └── flash_bridge.bat             # Script biên dịch và nạp nhanh ESP32-S3 trên Windows
```

## Đấu dây UART
| K230 (header 40 chân) | ESP32-S3 DevKitC-1 |
|---|---|
| Chân 8 `TX1` (`IO3`) | `GPIO18` (`RX`) |
| Chân 10 `RX1` (`IO4`) | `GPIO17` (`TX`) |
| `GND` | `GND` *(bắt buộc)* |

Tốc độ `921600 baud`, cả hai bo đều dùng mức logic `3.3V` nên nối trực tiếp.

## Giao thức UART (văn bản ASCII, kết thúc bằng `\n`)
- **K230 → ESP32**:
  - `FALL,<track_id>,<độ_tin_cậy_0..1>,<mốc_ms>`
  - `IP,<ip>,<cổng>,<đường_dẫn>` (địa chỉ luồng MJPEG, ví dụ `IP,192.168.1.50,81,/stream`)
  - `HB,<fps>,<số_người>` (nhịp tim mỗi 5 giây)
  - `LOG,<nội_dung>` (ESP32 in ra Serial với tiền tố `[K230]`)
- **ESP32 → K230**:
  - `CFG,<mã_nhà>,<mã_máy>,<địa_chỉ_relay>`
  - `SNAP,<mã_sự_kiện>,<phiếu_tải_ảnh>`

## ESP32-S3: Biên dịch và nạp
1. Tạo `include/device_secrets.h` từ `include/device_secrets.example.h`, điền Wi-Fi, token bot, chat ID (hoặc để trống và cấu hình sau từ ứng dụng qua BLE).
2. Biên dịch kiểm tra (từ thư mục `firmware/camera-k230/`):
   ```powershell
   pio run -e camera_bridge
   ```
3. Nạp vào mạch (cắm cổng micro-USB ghi **`UART`** trên bo DevKitC-1):
   ```powershell
   scripts\flash_bridge.bat COM3
   ```

## CanMV K230: Cài đặt và chạy
- Mở [`k230/falldown_detect.py`](k230/falldown_detect.py) bằng **CanMV IDE** và chép vào K230.
- Đặt model tại `/sdcard/examples/kmodel/yolov5n-falldown.kmodel`.
- Chỉnh `WIFI_SSID` và `WIFI_PASSWORD` trong lớp `CFG`.
- Ảnh bằng chứng được lưu tại `/sdcard/falls` và tự động đẩy lên Relay khi ESP32 cấp phiếu `SNAP`.
