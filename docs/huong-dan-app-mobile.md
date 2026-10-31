# Hướng dẫn cài đặt và sử dụng ứng dụng Báo Ngã IoT (Android & iOS Sideloadly)

Tài liệu hướng dẫn cài đặt bản `.apk` (Android) và bản `.ipa` chưa ký (iPhone/iPad qua **Sideloadly** bằng Apple ID miễn phí), cấp quyền chạy nền để không bỏ lỡ "thời gian vàng", ghép nối thiết bị và kiểm tra độ trễ cảnh báo.

---

## 1. Cài đặt trên Android (`.apk`)

### Nguồn file cài đặt
- **Đã đóng gói sẵn trên máy này**: `D:\dev-tools\artifacts\app-arm64-v8a-release.apk` (~25 MB, dành cho hầu hết điện thoại Android 64-bit hiện nay) hoặc `D:\dev-tools\artifacts\app-release.apk` (~68 MB, bản đa kiến trúc).
- **Hoặc tải từ GitHub Actions**: Vào tab **Actions** → workflow **build-mobile** → tải gói **`baonga-android`**.

### Các bước cài đặt & cấp quyền bắt buộc
1. Chép file `app-arm64-v8a-release.apk` sang điện thoại Android và mở để cài đặt (cho phép "Cài đặt ứng dụng không rõ nguồn gốc" nếu được hỏi).
2. Mở ứng dụng **Báo Ngã IoT** → sang tab **Cài đặt & SOS** → mục **Ứng dụng**:
   - Bấm **Cấp quyền** để cho phép **Thông báo**, **Bluetooth** (tìm thiết bị lân cận) và **Camera** (quét mã QR).
   - Bật **Giám sát nền (foreground service)** (mặc định bật).
   - Bấm **Bỏ tối ưu pin** → chọn **Cho phép / Không hạn chế** để Android không đóng băng dịch vụ lắng nghe UDP/SSE khi khóa màn hình.
   - *(Trên Xiaomi/OPPO/Vivo/Samsung)*: Vào thông tin ứng dụng trong Cài đặt máy → bật thêm **Tự khởi động (Autostart)** và **Hiển thị trên màn hình khóa**.

---

## 2. Cài đặt trên iPhone / iPad bằng Sideloadly (`.ipa` với Apple ID miễn phí)

Bản iOS được cấu hình entitlements rỗng (`<dict/>`) để tương thích 100% với **Apple ID cá nhân miễn phí** (không cần tài khoản Apple Developer 99 USD/năm).

### Bước 1: Lấy file `baonga-ios-unsigned.ipa`
1. Đẩy code lên nhánh `main` trên GitHub (hoặc bấm **Run workflow** trong tab **Actions** → **build-mobile**).
2. Khi job `build-ios` hoàn tất (màu xanh), tải artifact **`baonga-ios-unsigned`** về máy tính Windows và giải nén để lấy file `baonga-ios-unsigned.ipa`.

### Bước 2: Ký và cài vào iPhone bằng Sideloadly
1. Trên Windows, cài đặt **iTunes** + **iCloud** (bản tải trực tiếp từ trang chủ Apple, không dùng bản Microsoft Store) và **Sideloadly** (`https://sideloadly.io`).
2. Cắm cáp nối iPhone với máy tính, bấm **Tin cậy (Trust)** trên iPhone.
3. Mở **Sideloadly**:
   - Kéo thả file `baonga-ios-unsigned.ipa` vào ô **IPA**.
   - Nhập email **Apple ID** của bạn vào ô **Apple account**.
   - Bấm **Start** (lần đầu sẽ nhập mật khẩu Apple ID và mã xác thực 2 lớp).
4. Trên iPhone sau khi cài xong:
   - Vào **Cài đặt (Settings) → Cài đặt chung (General) → Quản lý VPN & Thiết bị (VPN & Device Management)** → chọn Apple ID của bạn → bấm **Tin cậy (Trust)**.
   - *(Từ iOS 16 trở lên)*: Vào **Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển (Developer Mode)** → gạt **Bật** và khởi động lại máy.

### Bước 3: Tự gia hạn 7 ngày qua Wi-Fi & lưu ý chạy nền trên iOS
- Chứng chỉ Apple ID miễn phí có hiệu lực **7 ngày**. Mở biểu tượng **Sideloadly Daemon** dưới khay hệ thống Windows và bật **Auto-refresh over Wi-Fi** (khi máy tính và iPhone cùng mạng Wi-Fi, Sideloadly sẽ tự ký lại ngầm trước khi hết hạn mà không mất dữ liệu).
- **Quyền mạng nội bộ (Local Network)**: Lần đầu mở app trên iOS, bấm **Cho phép (Allow)** khi hệ thống hỏi quyền tìm thiết bị trên mạng cục bộ và Bluetooth.
- **Nhận cảnh báo nền trên iOS Sideloadly**:
  - Kênh **BLE tới Camera AI** hoạt động nền tự nhiên trên iOS (`bluetooth-central`).
  - Để nhận cảnh báo nền qua Wi-Fi/Cloud khi khóa máy (do Apple ID miễn phí không có APNs), vào tab **Cài đặt & SOS** → bật **Giữ ứng dụng hoạt động nền** và đừng vuốt tắt hẳn ứng dụng khỏi trình đa nhiệm.

---

## 3. Kết nối thiết bị & Ghép nối mã QR

### A. Vòng đeo TinyML
- **Từ xa qua Cloud**: Đăng nhập bằng tài khoản Firebase (Email / Mật khẩu). App mở luồng SSE trực tiếp tới nút `alert` để nhận cảnh báo tức thì từ bất kỳ đâu (4G/5G/Wi-Fi).
- **Cài Wi-Fi lần đầu qua Hotspot**: Nếu vòng đeo chưa có Wi-Fi, nối điện thoại vào mạng `BaoNga-Setup-XXXX`, mở app chọn **Cài đặt qua Hotspot BaoNga-Setup-XXXX** → vào mục **Wi-Fi 2.4 GHz của vòng đeo** để quét và lưu Wi-Fi nhà.
- **Nội mạng (LAN)**: Khi cùng Wi-Fi, app tự học IP của vòng đeo qua gói UDP `:4210` hoặc Cloud; cũng có thể nhập trực tiếp `http://baonga.local` hoặc `192.168.x.x` ở tab **Vòng đeo**.

### B. Camera AI K230 (Cầu nối BLE)
1. Tạo mã QR ghép nối cho từng thiết bị cầu nối (từ MAC BLE và khóa chủ trong `firmware/camera-k230/include/device_secrets.h`):
   ```powershell
   python mobile/tools/generate_qr.py --mac AA:BB:CC:DD:EE:FF --master <64_KY_TU_HEX> --out qr_camera.png
   ```
2. Trong app, mở tab **Camera AI** → bấm **Quét QR ghép nối** (hoặc **Nhập mã thủ công** chuỗi `cbn://pair?id=CBC-XXXXXX&key=...`).
3. Bấm **Quét camera** → bấm **Kết nối** vào `CBC-XXXXXX`. App sẽ tự xác thực HMAC-SHA256, nhận luồng cảnh báo BLE + trạng thái `ALIVE`, xem trực tiếp hình ảnh MJPEG và cho phép ghi cấu hình Wi-Fi/Telegram qua BLE.

---

## 4. Kiểm tra độ trễ cảnh báo ("Thời gian vàng")

1. Đảm bảo trên thanh tiêu đề của ứng dụng, các chip kênh đang dùng (**UDP**, **BLE**, **Cloud**, **LAN**) chuyển sang **màu xanh**.
2. Thử nghiệm:
   - **Gửi tin thử**: Vào tab **Cài đặt & SOS** → bấm **Gửi tin thử** để xác nhận kết nối tới thiết bị, Telegram và Gmail.
   - **Thử báo động té ngã thực tế**: Tạo tình huống rơi/ngã thử trên vòng đeo hoặc trước Camera AI.
3. Quan sát màn hình **Báo động khẩn cấp** màu đỏ tự bật lên kèm còi hú + rung:
   - Cùng Wi-Fi (**UDP `:4210`**) hoặc gần Camera (**BLE**): còi hú trong khoảng **50 – 300 ms** ngay cả khi mất Internet.
   - Khác mạng qua 4G/5G (**Firebase SSE + Fast-Flush**): còi hú trong khoảng **0.4 – 1.2 giây**.
   - Nếu cả Vòng đeo và Camera AI cùng phát hiện trong vòng **30 giây**, app **không hú lặp lần 2** mà nâng cấp trực tiếp nhãn thành **"ĐA NGUỒN XÁC NHẬN (Vòng đeo + Camera AI)"** và ghi rõ độ trễ từng kênh (`UDP 0 ms · BLE +120 ms · Cloud +680 ms`) trong tab **Nhật ký**.
