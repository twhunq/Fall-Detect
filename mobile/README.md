# Báo Ngã IoT — ứng dụng di động (Flutter)

Nhận cảnh báo té ngã từ vòng đeo TinyML và camera AI K230 qua 4 đường song song
(UDP LAN :4210, BLE, Firebase SSE, Web Portal nội mạng), hú còi + rung + màn hình
báo động đỏ khi đường nhanh nhất tới, khử trùng lặp và hợp nhất "Vòng đeo + Camera AI"
trong 30 giây. Android `.apk` và iOS `.ipa` chưa ký (cài bằng Sideloadly).

## Lệnh (PowerShell, từ thư mục gốc repo)
```powershell
. .\mobile\scripts\flutter_env.ps1   # bắt buộc: SDK/cache trên D:\dev-tools
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi   # cần scripts\setup_local_sdk.ps1 một lần
```
Dọn cache: `powershell -ExecutionPolicy Bypass -File mobile\scripts\clean_cache.ps1`.
IPA chưa ký được CI build trên macOS (`.github/workflows/build-mobile.yml`).

## Cấu trúc `lib/`
- `config.dart` — Firebase (từ `cloud/public/config.js`), UUID BLE, cổng UDP, cửa sổ hợp nhất.
- `core/` — Dart thuần, có test: `protocol/` (gói UDP, BLE/QR/HMAC/CFG, kiểm tra cài đặt
  khớp `notify_settings.h`, MJPEG, SSE), `fusion/` (`AlertFusionEngine`), `models/`.
- `services/` — Firebase REST + SSE, UDP, Web Portal, BLE (flutter_blue_plus), MJPEG,
  nhật ký, `MonitorEngine` (chạy được trong isolate nền).
- `platform/` — chuông/rung/thông báo, quyền, Foreground Service Android, `MonitorBackend`.
- `state/` — `AppController`; `ui/` — đăng nhập, 4 tab, màn hình báo động.

Giao thức phải khớp firmware: xem `README.md` ở thư mục gốc.
Mã QR ghép camera: `python mobile/tools/generate_qr.py --mac <MAC> --master <64 hex>`.
