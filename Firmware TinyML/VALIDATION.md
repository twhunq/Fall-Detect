# Kết quả kiểm tra — 2026-09-26

## Đã thực hiện trên máy tính

| Kiểm tra | Kết quả |
|---|---|
| Đối chiếu chân U1 trong PCB KiCad | SDA8, SCL9, INT7, TOUCH4, BUZZER5, LED6, ADC1 khớp |
| Compile firmware chính, Arduino-ESP32 3.3.8 | PASS: flash 354.608 byte, RAM tĩnh 25.072 byte |
| Compile sketch thu thập dữ liệu, cùng target | PASS: flash 335.120 byte, RAM tĩnh 28.856 byte |
| C++ so với NumPy/trọng số hiện có | PASS: 602 cửa sổ, cùng lớp dự đoán; sai lệch confidence <0,0001 |
| Thống kê trên bộ đệm vòng, đầu vào hằng và NaN | PASS |
| Cửa sổ đầu tiên, hop 10 mẫu, mất mẫu, tràn micros | PASS |
| Giữ cảnh báo, hủy, thời gian khóa, SOS, chống dội, tràn millis | PASS |
| WHO_AM_I, cấu hình rate/range, đổi dấu dữ liệu, NACK, đọc thiếu byte | PASS với I2C mô phỏng |
| SDA/SCL bị giữ LOW, khởi tạo lại bus, lỗi xác minh thanh ghi | PASS với I2C mô phỏng |
| Không upload binary cũ khi compile thất bại; không tự chọn COM1 không rõ thiết bị | PASS |
| Hai sketch có cùng driver và cấu hình | PASS |

Host test dùng C++17 với `-Wall -Wextra -Werror`, assertions luôn bật, NumPy 2.4.2 và Zig 0.13.0. Arduino CLI 1.5.2-rc.1, core ESP32 3.3.8. Build MCU dùng `--warnings all`; bản build đầu có cảnh báo khởi tạo struct từ header TinyUSB/ESP-IDF đi kèm core, không có cảnh báo trong nguồn firmware của dự án.

FQBN đã dùng:

```text
esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,PSRAM=disabled,FlashSize=4M,FlashMode=dio,PartitionScheme=default,CPUFreq=80
```

Binary hiện tại: `build/esp32s3/fall_detection_esp32/` và `build/esp32s3/data_collection/`. Dùng `flash.py` để biên dịch nguồn hiện tại và nạp đúng các offset của ESP32-S3. File build ESP32 cũ được giữ lại trong thư mục ban đầu nhưng không dùng trong quy trình mới.

## Bổ sung 2026-10-06: cảnh báo bất động

| Kiểm tra | Kết quả |
|---|---|
| Host test toàn bộ (`run_tests.py`, Zig 0.13.0, `-Wall -Wextra -Werror`) | PASS, thêm `inactivity_test` |
| Bất động: thở/tim đập/nhiễu mô phỏng không tính là cử động; 1 cảnh báo khi quá giới hạn, không lặp; cử động/chạm → "cử động lại"; xung 2 mẫu bỏ qua; tràn millis | PASS |
| Tin Telegram/Gmail bất động và cử động lại, vừa bộ đệm | PASS |
| Cài đặt `inactiveMin` (0–1440, từ chối số lẻ/âm/chữ), so sánh cài đặt | PASS |

## Lỗi cloud trên bo thật (2026-10-06) và cách sửa

Đo trên bo qua Serial: RAM trống ~133 KB trước Wi-Fi, ~77 KB sau Wi-Fi; mỗi phiên TLS chiếm ~46 KB (core 3.3.8: bộ đệm vào/ra 16 KB, giữ chứng chỉ máy chủ, không cấu hình được). Khi kết nối Firebase giữ mở và Telegram/Gmail gửi cùng lúc, RAM trống còn 4–6 KB: Gmail thất bại, `GET control` hết giờ (`HTTP -11`), mọi lần kết nối lại lỗi `esp-x509-crt-bundle: PK verify failed 0x4290` (RSA không cấp phát được bộ nhớ), cloud kẹt ở `WAIT`. Lỗi này cũng làm hỏng cảnh báo ngã thật nếu xảy ra khi cloud đang kết nối.

Sửa: `TlsGate` trong `notifier.h`, mỗi lúc chỉ một phiên TLS; cảnh báo được ưu tiên, cloud đóng kết nối và nhường khi có tin cần gửi, nhận lại sau mỗi lượt thử. `[STATUS]` có thêm `heap=trống/khối lớn nhất`. Sau khi sửa, đo trên bo: ~128 KB trống khi rảnh, ~83 KB khi cloud đang kết nối.

Còn lại khi kiểm tra: mạng là Personal Hotspot của iPhone (`172.20.10.x`), có lúc `HTTP -11` / `-1` dù RAM còn nhiều, sau đó thiết bị không vào được Wi-Fi trong 3 phút. Đây là vấn đề kết nối mạng, không phải firmware. Lần nạp cuối (chỉ thêm dòng log `[NOTIFY] Bat dau gui …`) bị lỗi USB `Write timeout`, chưa nạp được.

## Phần cứng và Wi-Fi, đo trên bo thật — 2026-10-06

| Kiểm tra | Kết quả |
|---|---|
| Chip | ESP32-S3, Flash 4 MB, **PSRAM 2 MB (QSPI)**: bật `PSRAM=enabled`, bộ đệm TLS và Wi-Fi nằm trong PSRAM; phân vùng `min_spiffs` |
| RAM nội khi Wi-Fi + cloud TLS + web | ~120–130 KB trống (trước khi dùng PSRAM có lúc tụt tới 1,8–6 KB, crash/khởi động lại) |
| Wi-Fi | Router "Nha Tro" -67…-73 dBm, kênh 12. 19,5 dBm và 11 dBm: liên tục ASSOC_EXPIRE/AUTH_EXPIRE/4-way timeout; 8,5 dBm: kết nối được (`WIFI_TX_POWER`) |

Lỗi đã sửa nhờ đo trên bo: tin TEST tự gửi sau khởi động (đọc vùng nhớ đã giải phóng trong `pollControl`), nhận nhầm chạy pin khi không gắn pin (chân ADC thả nổi ~2 V; nay dùng `HWCDC::isPlugged()`), log mạng bị rơi (bộ đệm Serial 64 byte → 4 KB), thử lần lượt mạng không có sóng (nay quét trước, vào thẳng BSSID/kênh).

## Cloud chậm/treo và Gmail không gửi — đo và sửa trên bo, 2026-10-06

| Lỗi | Nguyên nhân (đo trên bo) | Sửa | Sau khi sửa |
|---|---|---|---|
| Cloud mất vài phút mới đồng bộ, có lúc treo hẳn | `HTTPClient::getString()` chờ phần thân phản hồi **không giới hạn thời gian** khi kết nối còn mở; trên Wi-Fi yếu, tác vụ cloud đứng ở bước đăng nhập > 4 phút (log `[KET]`) | `readBody()` trong `cloud_sync.h`: tự đọc thân (Content-Length/chunked) với hạn 10 s, quá hạn thì đóng kết nối | Đồng bộ **5,5–9,5 s** sau khi có Wi-Fi (đăng nhập ~4–5 s, mở CSDL ~1–4 s) |
| Gmail luôn thất bại, Telegram vẫn gửi | Kết nối TLS tới smtp.gmail.com:465 thành công nhưng `readBytesUntil()` trên client TLS không nhận được lời chào `220` (máy tính cùng mạng nhận được sau 0,8 s) | `smtpReply()` tự đọc bằng `available()`/`read()` với một hạn chung; lỗi Gmail nay ghi rõ bước SMTP, mã trả về, số byte | `TEST: Telegram=OK Gmail=OK` |

Thêm `[KET]`: tác vụ mạng đứng ở một bước quá 30 s thì log tên bước.

## Chưa xác minh trên phần cứng

Lúc kiểm tra USB chỉ thấy COM1 không có nhận diện ESP32-S3. Chưa nạp vào bo, chưa đo timing/nguồn thực tế, chưa chạy bền dài hạn. Kết quả host dùng Wire/GPIO mô phỏng, không thay cho đo trên PCB. Mô hình giữ nguyên dữ liệu huấn luyện mô phỏng; chưa có kết quả độ nhạy/báo giả khi đeo thực tế.

## Các bước chạy thử trên PCB

1. Xác nhận flash của module hỗ trợ cấu hình trên, MPU6050 đúng loại, INT nối GPIO7, TTP223 active HIGH/nhấn nhả và còi chủ động đúng BOM.
2. Nạp firmware chính, mở Serial 115200. Kiểm tra `imu=OK model=OK`, dự đoán xuất hiện sau đủ một cửa sổ; theo dõi `err` và `gap` không tăng khi hoạt động bình thường.
3. Giữ chạm 3 giây để thử SOS: LED sáng, còi nhịp 300 ms. Thả tay không tắt; chạm ngắn lần nữa để hủy. Khởi động khi đang giữ chạm không được tạo SOS giả trước khi thả tay.
4. Cấp nguồn bằng pin, không cắm USB: cảm biến và cảnh báo phải hoạt động. So sánh log điện áp pin với đồng hồ tại VSW, đo 3V3 khi còi kêu và khi pin yếu; điều chỉnh hệ số đo nếu cần.
5. Thử ngắt kết nối cảm biến bằng đồ gá/ngắt nguồn phù hợp: LED báo lỗi, vẫn dùng được TTP223/SOS. Khi cảm biến trở lại, firmware tự khởi tạo và gom đủ mẫu mới. Báo động đã kích hoạt không tự tắt do cảm biến lỗi.
6. Nạp sketch thu thập, mỗi nhãn phải cho dòng CSV đủ 301 cột. Mất mẫu phải hủy cửa sổ thay vì in số cũ. Nạp lại firmware chính sau khi thu thập.
7. Thu và đánh giá dữ liệu ở đúng vị trí đeo; đo tỷ lệ bỏ sót/báo giả với sinh hoạt bình thường và thử nghiệm ngã có kiểm soát. Chạy bền 24–48 giờ, theo dõi số lỗi, khoảng trống mẫu, heap và các lần reset trước khi kết luận ổn định thực tế.
