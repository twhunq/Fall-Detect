# Firmware TinyML — ESP32-S3 Super Mini

Firmware cho PCB trong `../../hardware/pcb`, dùng MPU6050/GY-521, TTP223, còi chủ động 3 V, LED đỏ và cầu phân áp pin. Đã chuyển từ ESP32 sang ESP32-S3, giữ nguyên trọng số MLP 30→16→8→5 và thứ tự đặc trưng của Python.

## Chân nối đúng PCB

Đối chiếu trực tiếp các net của U1 trong `fall_detector.kicad_pcb` và pinout Super Mini:

| Chức năng | GPIO | Hoạt động |
|---|---:|---|
| MPU6050 SDA | 8 | I2C 400 kHz |
| MPU6050 SCL | 9 | I2C 400 kHz |
| MPU6050 INT | 7 | DATA_READY, HIGH, giữ mức đến khi đọc |
| TTP223 OUT | 4 | HIGH khi chạm, module ở chế độ nhấn nhả |
| Còi | 5 | HIGH bật Q1, dùng còi **chủ động** đúng BOM |
| LED ngoài PCB | 6 | HIGH sáng |
| Điện áp pin | 1 | ADC1, cầu R4/R5 100k/100k, nhân 2 |

GPIO48 là LED RGB trên Super Mini, **không phải** LED cảnh báo GPIO6. Firmware không sử dụng GPIO19/20 của USB, chân strapping hoặc chân flash/PSRAM. AD0 của MPU6050 nối GND, địa chỉ `0x68`. Driver kiểm tra WHO_AM_I = `0x68`; không nhận nhầm các chip MPU/ICM khác thành MPU6050.

## Biên dịch và nạp

Dùng **Arduino-ESP32 3.3.x** (tối thiểu 3.3.8, đã kiểm tra trên 3.3.8 và 3.3.12). Không cần thư viện MPU6050 hoặc TensorFlow Lite. Python 3 và Arduino CLI dùng cho các script; bản firmware có thể mở trực tiếp bằng Arduino IDE.

### Arduino IDE

Mở `src/fall_detection_esp32/fall_detection_esp32.ino`, chọn:

| Mục | Giá trị |
|---|---|
| Board | ESP32S3 Dev Module |
| USB Mode | Hardware CDC and JTAG |
| USB CDC On Boot | Enabled |
| CPU Frequency | 80 MHz |
| Flash Mode | DIO 80 MHz |
| Flash Size | 4 MB |
| Partition Scheme | Minimal SPIFFS (1.9MB APP with OTA/190KB SPIFFS) |
| PSRAM | QSPI PSRAM |
| Serial Monitor | 115200 baud |

Đây là cấu hình dùng vùng flash 4 MB, phù hợp bo có **ít nhất 4 MB flash hỗ trợ DIO**; hình pinout không xác định được dung lượng/loại flash của từng lô. Bo đã thử có PSRAM 2 MB (ESP32-S3FH4R2): bộ đệm TLS và Wi-Fi nằm trong PSRAM, nhờ vậy Wi-Fi + cloud + gửi cảnh báo + trang web đủ RAM. Bo không có PSRAM vẫn chạy (log `PSRAM khong co`) nhưng RAM sát giới hạn khi vừa đồng bộ cloud vừa gửi cảnh báo. Nếu board thực tế dùng cấu hình flash khác, xác nhận mã chip trước khi đổi thiết lập.

Firmware chạy ngay khi cấp nguồn pin, không chờ cắm USB hay mở Serial Monitor. Bật CDC theo [hướng dẫn Espressif](https://docs.espressif.com/projects/arduino-esp32/en/latest/tutorials/cdc_dfu_flash.html).

### Script Windows / CLI

Chạy trong thư mục `firmware/wearable`:

```powershell
# Lần đầu nếu chưa có core đúng phiên bản:
python scripts/flash.py --install-core --build-only

# Chỉ biên dịch, không ghi vào thiết bị:
python scripts/flash.py --build-only

# Biên dịch nguồn hiện tại rồi nạp; thay COM7 bằng cổng của bo thật:
python scripts/flash.py --port COM7

# Mở monitor tương tác, có thể nhập nhãn khi thu thập dữ liệu:
python scripts/serial_monitor.py --port COM7
```

Có thể dùng `scripts\\flash.bat --port COM7` và `scripts\\monitor.bat --port COM7`. Script tìm `arduino-cli` trong PATH, biến `ARDUINO_CLI`, Arduino IDE, hoặc bản đã tải trong `../../.tools/arduino-cli/`. Có thể chỉ định `--cli C:\duong-dan\arduino-cli.exe`.

Binary mới nằm trong `build/esp32s3/<ten_sketch>/`. Script luôn compile thành công trước khi upload bằng target ESP32-S3. Chỉ tự chọn cổng khi nhận diện duy nhất USB Espressif; cổng không rõ hoặc nhiều cổng cần chỉ định/chọn. Nếu chưa hiện USB: giữ BOOT, bấm rồi thả RESET, thả BOOT, kiểm tra lại COM. COM có thể thay đổi sau nạp.

## Hoạt động

- MPU6050 tự tạo mẫu **50 Hz**, lọc DLPF khoảng 21 Hz, ±4 g và ±500 °/s. Firmware đọc một burst chứa INT_STATUS và 6 kênh khi GPIO7 báo mẫu mới; không lặp mẫu cũ theo tốc độ vòng lặp.
- Lọc nhiễu (`imu_filter.h`): áp hiệu chỉnh (trừ bias gyro, căn trục để tư thế đứng thẳng → +Z như dữ liệu huấn luyện, chuẩn hóa |g| = 1), median 3 mẫu trên từng kênh để loại xung 1 mẫu (gõ vào vỏ, nhiễu I2C; trễ 20 ms), tự bám trôi gyro chậm khi thiết bị đứng yên ≥2 giây.
- Cửa sổ trượt 50 mẫu (1 giây), suy luận mỗi 10 mẫu (200 ms). Kết quả `nga` (confidence ≥70%) **không còn tự bật cảnh báo**, chỉ là một bằng chứng cho bộ xác nhận ngã.
- Xác nhận ngã (`fall_detector.h`), tham số trong `detection_config.h`:
  1. Phát hiện nghi ngã (*fall candidate*) khi có **va đập** |a| ≥ 2,0 g (sau lọc). Cử động nhẹ, đi bộ, vung tay không đạt ngưỡng này.
  2. Cần ít nhất một bằng chứng: rơi tự do |a| < 0,6 g trong 1 giây trước va đập, **hoặc** xoay ≥120 °/s quanh va đập, **hoặc** mô hình ML báo `nga` trong 1,5 giây sau va đập.
  3. Pha ổn định 1 giây (bỏ qua dội/lăn), rồi pha xác minh tư thế 2 giây: ≥80% mẫu phải nằm yên (||a|−1| < 0,2 g, gyro < 30 °/s) và tư thế lệch ≥45° so với tư thế trước va đập. Đứng dậy/đi tiếp hoặc chỉ ngồi phịch xuống sẽ bị loại.
  4. Cảnh báo bật khoảng 3 giây sau va đập. Mỗi sự kiện nghi ngã in một dòng `[FALL?] impact=… rot=… ff=… ml=… still=…% posture=…deg -> NGA/bo qua` để chỉnh ngưỡng trên dữ liệu đeo thật.
- Thứ tự đặc trưng giữ nguyên: từng kênh `ax, ay, az, gx, gy, gz`, mỗi kênh `[mean, std, min, max, rms]`. Trọng số và chuẩn hóa không đổi. Chỉ dùng mảng cố định; tính trực tiếp trên bộ đệm vòng vì các thống kê không phụ thuộc thứ tự mẫu.
- Nếu khoảng cách hai mẫu vượt 30 ms, loại cửa sổ đang gom và xóa chuỗi xác nhận ngã. Không ghép mẫu trước/sau lỗi, không tự điền mẫu giả.
- Timeout I2C 5 ms, kiểm tra kết quả ghi/đọc cấu hình. Mất dữ liệu 100 ms hoặc lỗi giao dịch sẽ báo lỗi, khởi tạo lại sau 2 giây, thử giải phóng bus bằng tối đa 9 xung SCL. Reset/đợi cảm biến theo trạng thái, không khóa vòng lặp hàng trăm ms. Xem [API I2C Espressif](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/i2c.html) và [register map MPU6050](https://invensense.tdk.com/wp-content/uploads/2015/02/MPU-6000-Register-Map.pdf).
- Watchdog vòng lặp 5 giây. Serial chỉ gửi khi có chỗ, không giữ việc giám sát để chờ máy tính. Wi-Fi chỉ bật khi đã điền `WIFI_SSID` (xem dưới); Bluetooth không dùng; chỉ deep sleep khi người dùng tắt thiết bị bằng giữ chạm 3 giây.

### Nguồn

Cấp 5V vào chân 5V của ESP32-S3 Super Mini. Vì không ngắt nguồn thật, "tắt" chỉ là deep sleep: khi tắt vẫn tiêu thụ dòng nhỏ (LDO, LED nguồn của Super Mini và GY-521, TTP223). Cấp nguồn lại thì thiết bị khởi động ở trạng thái bật; mất nguồn không giữ trạng thái tắt.

Về dòng khi ngủ: firmware đã đưa MPU6050 vào chế độ ngủ, tắt LED RGB, cô lập các chân GPIO nối ngoại vi và đánh thức bằng ext1 (cho phép tắt RTC_PERIPH); chip ESP32-S3 ngủ sâu khoảng 7–8 µA. Phần còn lại là phần cứng: LED nguồn của Super Mini và GY-521 khoảng 1–2 mA mỗi cái, WS2812 khi đen khoảng 0,3–1 mA, LDO 50–100 µA. Muốn giảm thêm thì gỡ điện trở của LED nguồn; nếu 5V lấy từ pin qua mạch boost thì chọn boost có dòng tĩnh thấp. Ước tính chưa đo: khoảng 3–6 mA khi còn LED, khoảng 0,1–0,2 mA sau khi gỡ LED.

### Chạm, còi và LED

| Thao tác / trạng thái | Kết quả |
|---|---|
| Phát hiện ngã | LED sáng liên tục, còi bật/tắt 300 ms |
| Chạm ngắn rồi thả khi đang báo | Tắt cảnh báo; tạm khóa báo ngã 10 giây, vẫn lấy mẫu |
| Giữ chạm 3 giây khi đang chạy | Bíp dài; thả tay → tắt (deep sleep). Hoạt động cả khi đang báo động, đang hiệu chỉnh hoặc MPU lỗi |
| Khi tắt: giữ chạm 3 giây | 2 bíp ngắn, thiết bị bật lại; chạm ngắn không bật |
| Chạm 3 lần trong 1,5 giây khi không báo động | Vào chế độ hiệu chỉnh (xem dưới) |
| LED nháy nhanh 5 Hz | Đang hiệu chỉnh, giữ yên |
| 2 tiếng bíp ngắn / 1 tiếng bíp dài | Hiệu chỉnh thành công / thất bại |
| LED nháy rất ngắn mỗi 2 giây | Giám sát bình thường |
| LED nháy 3 lần mỗi 2 giây | Cảm biến hoặc mô hình lỗi; ưu tiên hơn báo pin |
| LED nháy 2 lần mỗi 3 giây | Điện áp pin thấp |

**Đèn RGB trên bo Super Mini (GPIO48) báo trạng thái mạng**:

| Đèn RGB | Ý nghĩa |
|---|---|
| Xanh dương nhấp nháy nhanh | Đang quét/kết nối Wi-Fi, hoặc mất Wi-Fi |
| Xanh lá nhấp nháy chậm | Đã vào Wi-Fi nhưng chưa ra được Internet (cloud chưa đồng bộ) |
| Xanh lá sáng liên tục | Đã kết nối Internet (cloud đồng bộ; không dùng cloud thì là đã vào Wi-Fi) |
| Tím nhấp nháy | Đang phát Wi-Fi cài đặt `BaoNga-Setup-…` |
| Tắt | Wi-Fi không bật |

Cảnh báo được **giữ đến khi chạm hủy**, thay cho cơ chế tự tắt sau 5 giây của bản cũ. Lỗi cảm biến hoặc người đeo nằm yên không tự xóa cảnh báo. Mất nguồn/reset không lưu trạng thái báo động.

TTP223 cần chế độ momentary, active HIGH. Bỏ qua 1,5 giây đầu để ổn định cảm ứng, đợi thả tay trước khi nhận thao tác và chống dội 40 ms. Không chạm mặt cảm biến trong lúc cấp nguồn.

### Hiệu chỉnh (calib)

Làm một lần sau khi lắp thiết bị lên người, và làm lại nếu đổi vị trí/hướng đeo:

1. Đeo thiết bị đúng vị trí, đứng thẳng.
2. Chạm 3 lần liên tiếp vào TTP223 (hoặc gõ `calib` + Enter trong Serial Monitor).
3. LED nháy nhanh: firmware chờ 2 giây cho hết rung do chạm tay, rồi đo 3 giây. Giữ yên.
4. Thành công: 2 tiếng bíp ngắn, lưu vào NVS (giữ sau khi mất nguồn). Nếu bị rung, firmware tự đo lại; sau 20 giây vẫn không yên, hoặc |g| ngoài 0,85–1,15 g, sẽ bíp dài và giữ hiệu chỉnh cũ.

Hiệu chỉnh đo bias gyro, độ lớn trọng lực và hướng trọng lực khi đứng thẳng; mọi mẫu sau đó được xoay để tư thế đứng khớp trục Z của dữ liệu huấn luyện. Nhờ vậy, các trạng thái đứng/ngồi/nằm được phân loại đúng hơn và tư thế được so sánh chính xác hơn. Gõ `calib reset` để xóa. Chưa hiệu chỉnh thì firmware vẫn chạy, dùng trục gốc và tự học tư thế tham chiếu khi người đeo đứng yên. Giữ chạm 3 giây trong lúc hiệu chỉnh sẽ tắt thiết bị (hiệu chỉnh dở bị bỏ, hiệu chỉnh cũ được giữ). `[STATUS]` có thêm `cal=OK/NONE/RUN` và `det=IDLE/OBS`.

### Cảnh báo bất động

Phát hiện người đeo không cử động (có thể bất tỉnh):

- Thiết bị đếm thời gian từ lần **cử động thật** gần nhất: xoay >12 °/s hoặc gia tốc lệch >0,06 g so với trung bình gần đây, liên tục ≥60 ms. Thở, rung nhẹ của cơ thể không tính. Chạm vào cảm biến chạm cũng tính là cử động (người đeo còn tỉnh).
- Quá số phút đã đặt (mặc định **60**, `0` = tắt, tối đa 1440) thì gửi Telegram/Gmail **"CẢNH BÁO BẤT ĐỘNG"** kèm thời gian không cử động và pin; trang web hiện dải/popup màu vàng. Mỗi đợt chỉ gửi một lần; khi người đeo cử động lại thì gửi thêm tin **"ĐÃ CỬ ĐỘNG TRỞ LẠI"**.
- Cảnh báo này **không** bật còi/LED, để không đánh thức người đang ngủ. Đang báo ngã thì không gửi thêm cảnh báo bất động. Cảm biến lỗi thì khi hoạt động lại sẽ đếm từ đầu (không coi thời gian mất dữ liệu là nằm yên).
- Đổi số phút trên trang nội bộ (khung **Cảnh báo bất động**, bấm **Lưu cài đặt**) hoặc trang cloud. Giá trị được lưu NVS và đồng bộ hai chiều như người nhận.
- Khi ngủ, người lớn tuổi có thể nằm yên 30–90 phút: đặt thời gian dài hơn mức nằm yên thường ngày của người đeo. Tháo thiết bị đặt lên bàn cũng bị coi là bất động.
- `[STATUS]` có thêm `still=…s`, cùng `BAT_DONG` khi đã gửi cảnh báo. Có log `[INACTIVE]` khi gửi cảnh báo và khi cử động lại.

### Cảnh báo Telegram và Gmail

Chỉ gửi khi có **cảnh báo**: phát hiện ngã hoặc bất động quá thời gian đặt (và tin "đã cử động trở lại" sau đó). Chạm để tắt cảnh báo không gửi tin. Telegram nhận tin định dạng HTML (tiêu đề đậm, biểu tượng); Gmail nhận email HTML có dải tiêu đề màu (đỏ cho ngã, vàng cho bất động), bảng thông tin và ô hành động, kèm bản chữ thường cho trình đọc không hỗ trợ HTML, đánh dấu ưu tiên cao. Nội dung gồm thời gian (giờ Việt Nam, đồng bộ NTP), va đập, độ lệch tư thế và điện áp pin. Việc gửi chạy trong task riêng trên core 0: còi/LED và việc lấy mẫu không bị chậm khi mạng yếu. Mỗi tin thử lại tối đa 5 lần, cách nhau 5 giây. Kết nối TLS xác thực chứng chỉ máy chủ bằng bộ CA có sẵn trong core ESP32.

Cấu hình trong `src/fall_detection_esp32/secrets.h` (đã có trong `.gitignore`, **không commit**; xem mẫu `secrets.example.h`). Để trống token/tài khoản của kênh nào thì kênh đó không bật được; để trống `WIFI_SSID` thì Wi-Fi và trang web không bật. `TELEGRAM_CHAT_IDS` và `ALERT_EMAIL_TO` chỉ là giá trị ban đầu: sau khi nạp, người nhận và công tắc bật/tắt từng kênh được đổi trên trang web (xem dưới).

1. **Wi-Fi**: `WIFI_SSID`, `WIFI_PASSWORD` (mạng mặc định; sau này đổi trên trang web, xem "Cấu hình Wi-Fi"). Chỉ hỗ trợ băng tần 2,4 GHz.
2. **Telegram**: nhắn `/newbot` cho @BotFather, lấy token điền vào `TELEGRAM_BOT_TOKEN`. Gửi một tin bất kỳ cho bot (hoặc thêm bot vào nhóm gia đình), mở `https://api.telegram.org/bot<TOKEN>/getUpdates`, chép số trong `"chat":{"id":…}` vào `TELEGRAM_CHAT_IDS`. Nhiều người/nhóm thì phân cách bằng dấu phẩy.
3. **Gmail**: tài khoản gửi phải bật xác minh 2 bước, rồi tạo **App Password** (Tài khoản Google → Bảo mật → Mật khẩu ứng dụng). Điền `GMAIL_ADDRESS` và `GMAIL_APP_PASSWORD` (16 ký tự, có hay không có dấu cách đều được). **Không dùng mật khẩu Gmail thường.** `ALERT_EMAIL_TO` là người nhận, nhiều địa chỉ thì phân cách bằng dấu phẩy. Nên dùng một tài khoản Gmail riêng cho thiết bị.
4. Tùy chọn: `WEB_HOSTNAME` (mặc định `baonga`) và `WEB_PASSWORD` cho trang web.
5. Nạp lại, mở Serial và gõ `test notify` (hoặc bấm **Gửi tin thử** trên trang web) để gửi tin thử. Log hiện `[NET] Wi-Fi OK`, sau đó `[NOTIFY] … Telegram=OK Gmail=OK`. `[STATUS]` có thêm `net=OK/WAIT/OFF`.

Giới hạn: chỉ gửi được khi có Wi-Fi. Ra khỏi vùng phủ sóng thì cảnh báo chỉ còn còi/LED; tin chưa gửi được sẽ bị bỏ sau 5 lần thử. Wi-Fi (modem sleep) làm tăng dòng tiêu thụ, pin sẽ nhanh hết hơn so với bản tắt Wi-Fi. Mật khẩu nằm trong firmware: ai đọc được flash của thiết bị thì lấy được, vì vậy hãy dùng tài khoản/bot riêng và có thể thu hồi App Password khi mất thiết bị.

### Trang web trạng thái và cài đặt

Khi có Wi-Fi, thiết bị tự chạy một trang web trong mạng nội bộ. Điện thoại/máy tính phải cùng mạng Wi-Fi với thiết bị, mở `http://baonga.local` hoặc địa chỉ IP in trên Serial (`[NET] Wi-Fi OK, trang web: http://192.168.x.x/`). Trang không cần Internet và không tải thư viện ngoài.

- **Trạng thái đồng bộ** (cập nhật mỗi giây): đi bộ / đứng / ngồi / nằm / có dấu hiệu ngã kèm độ tin cậy của mô hình; dải đỏ khi đang báo **ngã**; tình trạng cảm biến, hiệu chỉnh, pin, sóng Wi-Fi, thời gian chạy; danh sách thay đổi hoạt động gần đây (lưu trong trình duyệt). "Có dấu hiệu ngã" là phán đoán tức thời của mô hình; chỉ khi thiết bị xác nhận ngã mới hiện dải cảnh báo và gửi tin. Mất kết nối 3 giây thì nhãn chuyển sang "Mất kết nối thiết bị".
- **Không cử động**: thời gian từ lần cử động gần nhất (ô trong khung Thiết bị); dải vàng khi đã gửi cảnh báo bất động.
- **Thông báo**: công tắc bật/tắt Telegram và Gmail; số phút **cảnh báo bất động**; ô **Chat ID** (số người dùng, số âm cho nhóm, `@ten_kenh` cho kênh công khai) và ô **email người nhận**. Mỗi ô tối đa 5 địa chỉ, cách nhau bằng dấu phẩy hoặc xuống dòng. Bấm **Lưu cài đặt**: thiết bị kiểm tra định dạng, áp dụng ngay và lưu vào bộ nhớ NVS (giữ nguyên sau khi tắt nguồn/nạp lại firmware). **Gửi tin thử** dùng cài đặt đã lưu, tối đa một lần mỗi 15 giây.
- Bot token và tài khoản Gmail gửi (App Password) vẫn chỉ nằm trong `secrets.h`, trang web không hiển thị và không đổi được chúng. Kênh chưa có thông tin này sẽ hiện ghi chú và không bật được.
- **Bảo mật**: đặt `WEB_PASSWORD` để trình duyệt hỏi mật khẩu (tên đăng nhập `admin`). Nếu để trống, bất kỳ ai trong cùng mạng Wi-Fi đều đổi được nơi nhận cảnh báo. Trang dùng HTTP thường, nên chỉ dùng trong mạng tin cậy, không mở cổng ra Internet. Lệnh ghi phải đến từ chính trang này (chặn trang web lạ gửi yêu cầu giả).
- Xóa cài đặt đã lưu để quay về giá trị trong `secrets.h`: xóa flash (`Erase All Flash Before Sketch Upload` trong Arduino IDE) rồi nạp lại.
- Tên `.local` cần mDNS: Android cũ và một số mạng không hỗ trợ, khi đó dùng địa chỉ IP (nên đặt IP cố định cho thiết bị trong router).

### Cấu hình Wi-Fi trên trang web của thiết bị

Trang **Wi-Fi** (`http://baonga.local/wifi`, hoặc nút **📶 Wi-Fi** trên trang chính) do chính ESP phát qua HTTP, dùng giống màn hình Wi-Fi của điện thoại. Trang cloud không đổi được Wi-Fi: nhập sai từ xa sẽ làm mất kết nối với thiết bị.

- Mở trang là tự quét; danh sách mạng có vạch sóng và 🔒. **Chạm vào một mạng** → nhập mật khẩu (mạng đã lưu hoặc mạng mở thì kết nối ngay) → trang hiện "Đang kết nối…" rồi báo **Đã kết nối** (kèm IP mới), **Sai mật khẩu** hoặc **Không tìm thấy mạng** (ngoài vùng sóng / mạng 5 GHz). **Mạng khác…** dùng cho mạng ẩn.
- Mạng chỉ được lưu khi kết nối thành công (tối đa 3, mạng mới nhất thử trước); kết nối thất bại thì thiết bị quay lại các mạng đã lưu. Mục **Mạng đã lưu** có nút **Quên**. Mật khẩu lưu trong NVS, không bao giờ gửi ngược lại trình duyệt.
- Khi thiết bị chuyển sang mạng khác, điện thoại có thể mất liên lạc với trang: kết nối điện thoại vào mạng mới rồi mở lại `http://baonga.local`.
- Thiết bị thử lần lượt các mạng đã lưu, mỗi mạng 12 giây. `WIFI_SSID`/`WIFI_PASSWORD` trong `secrets.h` chỉ là mạng mặc định lần đầu.
- **Điểm phát cài đặt**: không vào được mạng nào sau 45 giây (hoặc chưa lưu mạng nào), thiết bị phát Wi-Fi `BaoNga-Setup-XXXX` (mật khẩu = `WEB_PASSWORD` nếu dài từ 8 ký tự, nếu không thì không mật khẩu). Kết nối điện thoại vào đó, trang Wi-Fi tự mở (hoặc vào `http://192.168.4.1/wifi`). Thiết bị vẫn tiếp tục thử các mạng đã lưu; vào được mạng thì điểm phát tự đóng khi không còn ai dùng. Điểm phát mở tối đa 10 phút mỗi lần mất mạng để giữ pin; tắt/bật nguồn để mở lại. `WIFI_SETUP_AP 0` trong `secrets.h` tắt hẳn tính năng này.
- Trang dùng HTTP thường: chỉ cấu hình trong mạng tin cậy và nên đặt `WEB_PASSWORD`.
- Bảo vệ RAM: nếu RAM cạn (không còn khối ≥24 KB) suốt 60 giây và không có báo động/hiệu chỉnh, thiết bị ghi `[MEM]` rồi tự khởi động lại.

### Truy cập từ xa (Firebase)

Để xem trạng thái và đổi cài đặt từ **mạng bất kỳ** (4G, Wi-Fi nơi khác), thiết bị đồng bộ với Firebase Realtime Database. Trang web nằm trên Firebase Hosting (`https://<project>.web.app`), có HTTPS và đăng nhập. Thiết bị chỉ mở kết nối **đi ra** nên không cần mở cổng router, chạy được cả khi nhà mạng dùng CGNAT. Mã nguồn trang và luật bảo mật nằm trong thư mục `../../cloud/`.

Cách hoạt động: thiết bị gửi trạng thái khi có thay đổi (tối đa 2 giây một lần, cảnh báo ngã/bất động gửi ngay) và gửi nhịp "còn sống" mỗi 30 giây; cứ 5 giây đọc cài đặt và lệnh gửi thử từ cloud. Trang web nhận dữ liệu tức thời; không nhận nhịp quá 75 giây thì báo **"Thiết bị ngoại tuyến"**. Cài đặt đổi trên cloud được kiểm tra lại trên thiết bị như trang nội bộ; nếu bị từ chối, trang hiện lý do. Cài đặt đổi trên trang nội bộ được đẩy lên cloud (kể cả sau khi khởi động lại), lần đổi mới nhất ở đâu thì dùng ở đó. Bot token và App Password **không** được gửi lên cloud. Lưu lượng khoảng vài trăm MB/tháng, nằm trong gói miễn phí Spark của Firebase.

**Cài đặt một lần** (cần tài khoản Google; Node.js đã có để chạy `npx`):

1. Vào <https://console.firebase.google.com> → **Add project**, đặt tên (ví dụ `baonga-nha-toi`). Không cần Google Analytics.
2. **Build → Authentication → Get started → Sign-in method → Email/Password → Enable.** Tab **Users → Add user**, tạo:
   - tài khoản **cho thiết bị**, ví dụ `thietbi01@baonga.app` với mật khẩu dài ngẫu nhiên (email không cần có thật);
   - tài khoản **cho bạn** và người nhà (email thật để dùng được "Quên mật khẩu?").
   Chép cột **User UID** của từng tài khoản.
3. **Build → Realtime Database → Create database**, chọn vị trí **Singapore (asia-southeast1)**, chế độ **locked mode**. Chép địa chỉ database ở đầu tab Data (dạng `https://…firebasedatabase.app`).
4. Tab **Data**, bấm **+** ở gốc để tạo cây quyền (thay `<UID…>` bằng UID ở bước 2):
   ```
   access
     baonga-01
       <UID thiết bị>:  "device"
       <UID của bạn>:   "owner"     (xem và đổi cài đặt)
       <UID người nhà>: "viewer"    (chỉ xem)
   ```
   Chỉ console mới sửa được `access`; trang web và thiết bị không tự cấp quyền được.
5. **Project settings (bánh răng) → General → Your apps → biểu tượng `</>`** để đăng ký web app (không cần bật Hosting ở bước này). Chép `firebaseConfig` vào `../../cloud/public/config.js`.
6. Triển khai trang và luật bảo mật (thay `ten-project` bằng Project ID):
   ```powershell
   cd ../../cloud
   npx firebase-tools login
   npx firebase-tools deploy --project ten-project
   ```
   Lệnh này đưa `database.rules.json` (luật đọc/ghi) và thư mục `public/` lên. Kết quả in ra địa chỉ `https://ten-project.web.app`.
7. Trong `secrets.h` của firmware, điền `FIREBASE_API_KEY` (Project settings → General → Web API Key), `FIREBASE_DB_URL` (bước 3, không có `/` ở cuối), `FIREBASE_DEVICE_EMAIL` / `FIREBASE_DEVICE_PASSWORD` (tài khoản thiết bị ở bước 2) và `CLOUD_DEVICE_ID` (giống `deviceId` trong `config.js`). Nạp lại firmware.
8. Serial hiện `[CLOUD] Da dong bo Firebase`, dòng `[STATUS]` có `cloud=OK`; trang nội bộ có ô **Cloud: Đã đồng bộ**. Mở `https://ten-project.web.app`, đăng nhập bằng tài khoản của bạn.

**Tốc độ đồng bộ và mạng**: mỗi lúc thiết bị chỉ mở một kết nối HTTPS (RAM chỉ đủ cho một phiên TLS ~46 KB); khi có cảnh báo, cloud nhường kết nối cho Telegram/Gmail rồi đồng bộ lại. Khi cắm USB không có pin (`bat` < 2 V), Wi-Fi tắt chế độ tiết kiệm điện để phản hồi nhanh; chạy pin thì bật lại (và tắt tạm thời trong lúc gửi cảnh báo). Mất Internet thì thử lại sau tối đa 8 giây. Log `TLS -0x0001 (khong ket noi duoc Internet)` nghĩa là mạng Wi-Fi không ra được Internet. Điểm truy cập cá nhân của điện thoại hay chập chờn với ESP32: nên dùng router, hoặc trên iPhone bật **Tối đa hóa khả năng tương thích** và giữ màn hình Điểm truy cập cá nhân mở khi thử.

**Cập nhật từ bản trước** (đã triển khai cloud trước khi có cảnh báo bất động): chạy lại `npx firebase-tools deploy --project ten-project` trong `cloud/` **trước khi** nạp firmware mới. Luật cũ chặn trường `inactiveMin`: trang cloud không lưu được cài đặt (lỗi `PERMISSION_DENIED`) và thiết bị không đẩy được cài đặt đổi trên trang nội bộ lên cloud (log `[CLOUD] PUT control/settings loi HTTP 401`, đồng bộ bị kẹt cho đến khi triển khai luật mới).

Gỡ lỗi: `cloud=AUTH` hoặc `Dang nhap Firebase loi: INVALID_LOGIN_CREDENTIALS` là sai email/mật khẩu thiết bị hoặc sai API key (thiết bị thử lại sau 5 phút). `loi HTTP 401` là tài khoản thiết bị chưa có `"device"` trong `access/<CLOUD_DEVICE_ID>`. Trang báo "Tài khoản chưa được cấp quyền" sẽ hiện đúng đường dẫn `access/…` cần thêm cho tài khoản đang đăng nhập.

Bảo mật: chỉ tài khoản có trong `access/<mã thiết bị>` mới đọc được dữ liệu; chỉ `owner` (và chính thiết bị) mới đổi được cài đặt; chỉ thiết bị mới ghi được trạng thái. `config.js` (API key web) được phép công khai, quyền truy cập do luật database quyết định. Mật khẩu tài khoản thiết bị nằm trong flash: nếu mất thiết bị, vào Authentication tắt hoặc xóa tài khoản đó. Có thể tắt đăng ký tài khoản mới trong Authentication → Settings → User actions (tài khoản lạ dù tạo được cũng không đọc được gì).

Thêm thiết bị thứ hai: đặt `CLOUD_DEVICE_ID` khác (ví dụ `baonga-02`), tạo tài khoản thiết bị và cây `access/baonga-02` tương tự, mở trang với `?device=baonga-02`.

### Đo pin và nguồn

ADC đọc millivolt đã hiệu chuẩn bởi core, trung bình 16 lần (mỗi lần cách 100 ms), nhân hệ số 2. Báo thấp sau 3 đợt trung bình <3,50 V; bỏ báo sau 3 đợt ≥3,70 V. Dưới 2 V được coi là không có pin/công tắc tắt; chỉ là chẩn đoán điện áp, không phải phần trăm dung lượng hay bảo vệ xả. [API ADC Espressif](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/adc.html).

Theo net PCB, cầu phân áp đo **VSW trước diode D2**, không phải đường 5 V sau diode. Chỉnh `BATTERY_SCALE` bằng đồng hồ đo nếu cần. Ngưỡng thấp chỉ báo, không tự tắt máy.

Đường nguồn hiện tại là Li-Po → D2 → chân 5V → LDO 3V3 của Super Mini. Khi pin giảm, sụt áp diode/LDO có thể làm 3V3 mất ổn định; cần đo thực tế khi còi đang kêu. Đây là giới hạn phần cứng mà firmware không khắc phục được. Kiểm tra thêm điện áp cấp MPU trên module GY-521 thực tế vì các lô có thể có LDO riêng.

## Thu thập dữ liệu thật

```powershell
python scripts/flash.py --sketch data_collection --port COM7
python scripts/serial_monitor.py --port COM7
```

Gõ `dung`, `ngoi`, `nam`, `di_bo` hoặc `nga`, Enter để ghi 50 mẫu mới. CSV có **301 cột**: nhãn và 300 số. Giữ các dòng CSV đầy đủ, bỏ dòng log bắt đầu bằng `[`. Mất mẫu/lỗi I2C sẽ hủy cả cửa sổ. USB rút giữa lúc gửi có thể làm dòng CSV chưa hoàn chỉnh; bỏ dòng đó.

Sketch thu thập dùng cùng cấu hình MPU và chân với firmware chính; còi luôn tắt. Không dùng sketch này để giám sát ngã. Hai file `board_config.h` và `mpu6050_i2c.h` được giữ giống nhau trong hai thư mục để mở từng sketch độc lập bằng IDE. Sửa bản trong `fall_detection_esp32` rồi đồng bộ sang `data_collection`; bộ kiểm thử phát hiện khác biệt.

Mô hình hiện tại được huấn luyện từ `ml/data/synthetic_imu_data.npz`. Con số 100% trong header là kết quả trên dữ liệu mô phỏng, **không chứng minh hiệu quả phát hiện ngã ngoài thực tế**. Cần thu dữ liệu cùng vị trí đeo, hướng trục, bộ lọc/range mới và đánh giá bỏ sót/báo giả. ±4 g/±500 °/s có thể bão hòa khi va đập mạnh; đổi range phải đi kèm thu thập và huấn luyện lại. Hiệu chỉnh chỉ xoay trục, chuẩn hóa |g| và trừ bias gyro, không trừ trọng lực, để giữ dạng đầu vào đã huấn luyện. Sketch thu thập vẫn xuất dữ liệu **thô**; muốn huấn luyện lại bằng dữ liệu thật thì cần thêm hiệu chỉnh và lọc tương tự vào sketch đó, để dữ liệu thu được khớp với đầu vào firmware chính.

Quy trình huấn luyện nằm trong `ml/`:

```powershell
python -m pip install -r ml/requirements.txt
python ml/generate_synthetic_data.py
python ml/train_model.py
```

`train_model.py` hiện đọc NPZ mô phỏng. Muốn dùng CSV thật, cần chuyển thành dữ liệu huấn luyện phù hợp và sửa phần nạp dữ liệu; không có cơ chế tự huấn luyện từ CSV. Script xuất trực tiếp `src/fall_detection_esp32/model_weights.h` (nguồn sự thật duy nhất). Không sửa trọng số bằng tay.

## Kiểm thử

```powershell
# Cần NumPy và g++/clang++ hoặc Zig:
python tests/run_tests.py
python scripts/flash.py --build-only
python scripts/flash.py --build-only --sketch data_collection
```

Kiểm thử host (`detection_test.cpp`) mô phỏng: ngã thật, cử động nhẹ khi ML báo nhầm `nga`, đi bộ, ngồi phịch xuống, ngã rồi đứng dậy, gõ vào vỏ, mất mẫu khi đang quan sát, thiết bị lắp lệch trục, tràn millis; hiệu chỉnh với lắp lệch/lộn ngược/rung/|g| sai. Ngoài ra kiểm tra: mất mẫu và cửa sổ trượt, tràn millis/micros, giữ/hủy cảnh báo, chống dội/giữ chạm, không tràn bộ đếm, NaN, WHO_AM_I sai, lỗi ghi/đọc I2C, đọc thiếu byte, dữ liệu có dấu và phục hồi cảm biến. Đối chiếu đặc trưng/chuẩn hóa/suy luận C++ với NumPy trên 600 cửa sổ mô phỏng và 2 cửa sổ hằng. Đây là kiểm tra tương thích phép tính, không phải đo độ chính xác trên người dùng.

`inactivity_test.cpp` mô phỏng người đeo nằm yên (thở làm nghiêng thân, tim đập làm rung ngực, nhiễu và lệch 0 của MPU6050) qua bộ lọc thật: những rung đó không bị tính là cử động; một cảnh báo khi quá thời gian, không lặp; cử động/chạm thì báo cử động lại; bỏ qua xung 2 mẫu; tràn millis.

`notify_test.cpp` và `cloud_test.cpp` kiểm tra nội dung tin cảnh báo, kiểm tra Chat ID/email nhập từ trang web (chặn ký tự có thể chèn lệnh SMTP/JSON) và bộ đọc JSON trả về từ Firebase.

Xem `../../docs/validation.md` để biết kết quả đã chạy và các bước kiểm tra trên PCB còn cần thực hiện.
