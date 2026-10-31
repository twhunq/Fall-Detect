'''
Thực nghiệm : Phát hiện té ngã (bản nâng cấp)
Nền tảng    : 01Studio CanMV K230
Gốc         : wiki.01studio.cc - falldown_detection

=== CHỈNH DISPLAY_MODE Ở CLASS CFG BÊN DƯỚI NẾU MÀN ĐEN ===

Cải tiến so với bản demo gốc:
  1. Giải phóng tài nguyên đúng cách (try/finally) -> không kẹt VB buffer,
     không phải reset board sau mỗi lần nhấn Stop
  2. IoU tracker -> theo dõi trạng thái theo TỪNG người trong khung hình
  3. Bỏ phiếu M-trong-N + xác nhận theo thời lượng -> giảm mạnh báo động giả
  4. Tín hiệu phụ: tỉ lệ khung bbox (nằm/đứng) + tốc độ rơi của tâm bbox
  5. Máy trạng thái NORMAL -> SUSPECT -> ALARM -> RECOVERED, có cooldown
  6. Hook cảnh báo: UART sang ESP32-S3 / lưu ảnh bằng chứng / đẩy ảnh lên relay
  7. Đo FPS thật, gc.collect() có tiết chế, không spam log serial
'''

from libs.PipeLine import PipeLine
from libs.AIBase import AIBase
from libs.AI2D import Ai2d
from libs.Utils import *
import os, sys, gc, time
from media.media import *
import nncase_runtime as nn
import ulab.numpy as np
import image
import aicube


# ScopedTiming nằm ở libs.Utils hoặc libs.PipeLine tuỳ phiên bản SDK
try:
    ScopedTiming
except NameError:
    from libs.PipeLine import ScopedTiming


# ------------------------------------------------------------
# MicroPython chỉ có os rút gọn, KHÔNG có submodule path.
# Phải tự viết hàm kiểm tra tồn tại bằng os.stat().
# ------------------------------------------------------------
def file_exists(path):
    try:
        os.stat(path)
        return True
    except OSError:
        return False


# ============================================================
# CẤU HÌNH - chỉ cần sửa trong class này
# ============================================================
class CFG:
    # --- HIỂN THỊ ---
    # Màn MIPI gắn trên module   -> "lcd" (mặc định = st7701)
    # Nếu vẫn đen, thử lần lượt  -> "st7701" / "hx8399" / "jd9852" / "ili9806"
    #                               / "nt35516" / "nt35532" / "gc9503" / "aml020t"
    # Màn HDMI ngoài             -> "hdmi" (mặc định = lt9611)
    # Xem trong CanMV IDE        -> "virt"  VÀ đặt DISPLAY_SIZE = [800, 480]
    DISPLAY_MODE     = "lcd"
    DISPLAY_SIZE     = None          # None = tự lấy độ phân giải của màn
                                     # BẮT BUỘC đặt [800,480] nếu dùng "virt"

    # --- CAMERA ---
    # 640x360 thay vì 1280x720: nhẹ hơn cho luồng xem và ảnh bằng chứng, model
    # vẫn nhận đầu vào 640x640 nên độ chính xác gần như không đổi.
    RGB888P_SIZE     = [640, 360]
    SENSOR_ID        = None          # None = mặc định; đổi số nếu dùng CSI khác

    # --- MODEL ---
    KMODEL_PATH      = "/sdcard/examples/kmodel/yolov5n-falldown.kmodel"
    MODEL_INPUT_SIZE = [640, 640]
    LABELS           = ["Fall", "NoFall"]
    ANCHORS          = [10,13, 16,30, 33,23, 30,61, 62,45,
                        59,119, 116,90, 156,198, 373,326]
    CONF_TH          = 0.30
    NMS_TH           = 0.45
    STRIDES          = [8, 16, 32]

    # --- LOGIC THỜI GIAN (phần chống báo động giả) ---
    VOTE_WINDOW      = 10      # N: kích thước cửa sổ trượt (frame)
    VOTE_MIN         = 6       # M: cần >= M frame "ngã" trong N frame
    CONFIRM_MS       = 1500    # giữ trạng thái nghi ngờ >= 1.5s mới báo động
    LOST_MS          = 2000    # mất dấu quá 2s thì xoá track
    COOLDOWN_MS      = 15000   # sau 1 báo động, im lặng 15s
    RECOVER_MS       = 3000    # đứng dậy giữ >= 3s -> huỷ báo động

    # --- TÍN HIỆU PHỤ HÌNH HỌC ---
    USE_GEOMETRY     = True
    AR_LYING         = 0.95    # w/h > ngưỡng -> tư thế nằm
    DROP_RATIO       = 0.18    # tâm bbox tụt > 18% chiều cao khung
    DROP_WINDOW      = 8       # số frame để đo tốc độ rơi

    # --- TRACKER ---
    IOU_MATCH_TH     = 0.30

    # --- LƯU ẢNH BẰNG CHỨNG LÊN THẺ NHỚ ---
    ENABLE_SNAPSHOT  = True
    SNAPSHOT_DIR     = "/sdcard/falls"

    # --- UART SANG ESP32-S3 (cầu nối BLE + mạng) ---
    # K230 lo phần nhìn, ESP32-S3 lo phần báo tin. Xem đầu file
    # src/main.cpp để biết giao thức đầy đủ.
    #
    # Đấu dây theo header 40 chân của 01Studio CanMV K230:
    #   chân 8  TX1 (IO3)  -> ESP32-S3 GPIO18 (RX)
    #   chân 10 RX1 (IO4)  <- ESP32-S3 GPIO17 (TX)
    #   chân 6 hoặc 9 GND  <-> GND   (BẮT BUỘC, thiếu là dữ liệu ra rác)
    #   chân 2 hoặc 4  5V   -> chân 5V của ESP32 nếu lấy điện từ K230
    #
    # ĐỪNG dùng IO11/IO12: trên header này chúng là SCL2/SDA2, tức chân I2C.
    # Gán chức năng UART cho chúng thì UART vẫn mở được mà không có gì đi ra
    # dây - đúng kiểu hỏng im lặng, rất khó lần ra.
    ENABLE_UART      = True
    UART_PORT        = 1       # UART1; UART0 dành cho REPL, đừng đụng vào
    UART_TX_PIN      = 3       # IO3  = chân 8 trên header
    UART_RX_PIN      = 4       # IO4  = chân 10 trên header
    UART_BAUD        = 921600  # phải khớp UART_BAUD bên ESP32; báo càng sớm càng tốt
    HEARTBEAT_MS     = 5000    # nhịp báo "còn sống" gửi sang ESP32

    # --- ẢNH BẰNG CHỨNG ---
    # CHỈ nén MỘT lần. Mỗi lần nén phải xin một bộ đệm RGB888 vài megabyte từ
    # chung kho buffer với đường hiển thị; nén nhiều lần liên tiếp làm cạn kho
    # đó và màn hình tắt luôn cho tới khi khởi động lại.
    IMG_QUALITY      = 45

    # Số hiệu bản. In ra lúc khởi động để biết bo đang chạy đúng file nào -
    # nhiều lần sửa xong mà bo vẫn chạy bản cũ, mất công thử lại từ đầu.
    VERSION          = "2026-10-20 don-code"
    # Ngưỡng nghi ngờ ảnh trắng. PHẢI chỉnh theo độ phân giải: ở 640x360 một
    # cảnh đơn giản nén ra 5-7KB là bình thường, đặt 8000 như hồi 1280x720 sẽ
    # vứt nhầm ảnh tốt. Để thấp, chỉ đủ bắt trường hợp ảnh rỗng hoàn toàn.
    IMG_MIN_BYTES    = 1200
    # Tắt hẳn phần ảnh nếu nó còn gây rắc rối. Cảnh báo vẫn gửi bình thường,
    # chỉ là không kèm ảnh.
    ENABLE_EVIDENCE  = True

    # --- WIFI CỦA K230 (kênh hình ảnh) ---
    # Video KHÔNG đi qua ESP32: UART 921600 baud chỉ được ~90KB/s, một ảnh
    # JPEG đã 30KB nên nhiều lắm là 3 hình/giây - không thành video.
    # Vì vậy K230 tự nối WiFi và tự phát hình.
    ENABLE_WIFI      = True
    WIFI_SSID        = "Marine"
    WIFI_PASSWORD    = "88889999"
    WIFI_TIMEOUT_MS  = 15000

    # --- XEM TRỰC TIẾP TRONG MẠNG NHÀ (MJPEG) ---
    # Điện thoại cùng WiFi mở được http://<ip_k230>:81/stream
    # Ra khỏi nhà thì không xem được - muốn xem từ xa phải có WebRTC hoặc
    # dịch vụ xuyên NAT, nằm ngoài phạm vi đề tài.
    ENABLE_STREAM    = True
    STREAM_PORT      = 81
    STREAM_PATH      = "/stream"
    STREAM_QUALITY   = 50      # 1-100. Cao quá thì ảnh nặng, làm tụt FPS
    STREAM_EVERY     = 3       # chỉ đẩy 1 khung mỗi N khung, để dành sức cho
                               # việc phát hiện ngã - đó mới là việc chính

    # --- ĐẨY ẢNH BẰNG CHỨNG LÊN SERVER ---
    # Người nhà ở xa cần NHÌN THẤY lúc ngã, không chỉ đọc một dòng chữ.
    # Để trống RELAY_URL thì bỏ qua phần này, mọi thứ khác vẫn chạy.
    RELAY_URL        = ""      # ví dụ "https://canhbaonga.vercel.app"
    UPLOAD_TIMEOUT_S = 8

    # --- VẬN HÀNH ---
    GC_EVERY         = 20      # gọi gc.collect() mỗi N frame
    FPS_EVERY        = 30      # cập nhật FPS mỗi N frame
    DEBUG            = 0


# ============================================================
# NÉN ẢNH - dùng chung cho luồng xem trực tiếp và ảnh bằng chứng
#
# API ảnh khác nhau giữa các bản SDK CanMV. Nén ảnh hỏng KHÔNG được phép làm
# chết vòng lặp phát hiện ngã - mất hình chỉ là bất tiện.
# ============================================================
# K230 chạy thẳng từ thẻ nhớ nên bình thường không có console nào để đọc.
# Đẩy log chẩn đoán sang ESP32 qua cùng sợi UART, nó in ra cổng USB của nó.
# Giữ nguyên ASCII: log đi xuyên hai con chip và một cửa sổ terminal Windows.
_uart_log = None


def dlog(msg):
    print(msg)
    try:
        if _uart_log is not None:
            _uart_log("LOG,%s\n" % msg.replace("\n", " "))
    except Exception:
        pass


def _compress(img, quality):
    """Nén một image.Image thành bytes JPEG. Trả None nếu bản SDK không chiều."""
    if img is None:
        return None
    try:
        try:
            out = img.compress(quality=quality)
        except TypeError:
            out = img.compress(quality)          # bản cũ nhận tham số vị trí
        target = out if hasattr(out, "bytearray") else img
        return bytes(target.bytearray())
    except Exception as e:
        print("[WARN] Nén ảnh thất bại:", e)
        return None


def grab_jpeg(img_np, wh, quality):
    """Ảnh bằng chứng (xám), dựng TỪ BỘ ĐỆM AI.

    KHÔNG gọi sensor.snapshot(): kênh đó đang nuôi đường hiển thị, giành buffer
    của nó giữa lúc pipeline chạy sẽ treo máy rồi watchdog reset bo.

    Bộ đệm là PLANAR (trọn mặt phẳng đỏ, rồi lục, rồi lam), không xen kẽ theo
    điểm ảnh. Nên cắt riêng mặt phẳng lục làm ảnh xám: không có gì để diễn giải
    sai, còn ghép màu phải xen kẽ 690KB bằng Python - quá chậm lúc báo động."""
    w, h = wh
    try:
        phang = img_np.reshape(-1)
        xam = image.Image(w, h, image.GRAYSCALE, alloc=image.ALLOC_REF,
                          data=phang[w * h:2 * w * h])
        data = _compress(xam, quality)
    except Exception as e:
        dlog("anh xam loi: %s" % e)
        data = None

    if data and len(data) >= CFG.IMG_MIN_BYTES:
        return data
    dlog("KHONG dung duoc anh coi duoc")
    return None


def encode_jpeg(img_np, wh, quality):
    try:
        w, h = wh
        frame = image.Image(w, h, image.RGBP888,
                            alloc=image.ALLOC_REF, data=img_np)
        return _compress(frame.to_rgb888(), quality)
    except Exception as e:
        print("[WARN] Nén ảnh thất bại:", e)
        return None


# ============================================================
# MẠNG - WiFi riêng của K230, luồng xem trực tiếp, đẩy ảnh lên server
#
# VÌ SAO KÊNH HÌNH KHÔNG ĐI QUA ESP32: UART 921600 baud được khoảng 90KB/s,
# một ảnh JPEG 640x480 nặng chừng 30KB -> nhiều lắm 3 hình/giây. Không thành
# video được. Nên K230 tự nối WiFi và tự phát hình, còn ESP32 chỉ lo đường sự
# kiện: nhẹ, nhanh, và là thứ quyết định người thân có được báo hay không.
# ============================================================
class NetLink:
    def __init__(self):
        self.wlan = None
        self.ip = None
        self.srv = None
        self.clients = []
        self.home_id = ""      # ESP32 gửi sang, để tiện tra cứu khi đọc log
        self.dev_id = ""
        self.relay_url = ""    # ESP32 gửi sang; CFG.RELAY_URL được ưu tiên

        # Ảnh bằng chứng đang chờ phiếu để đẩy lên. Giữ đúng MỘT tấm: cú ngã
        # tiếp theo có ảnh mới thì tấm cũ không còn ý nghĩa gì nữa.
        self.anh_cho = None
        self._n = 0

        self._wifi_at = 0        # mốc bắt đầu quay số, 0 = chưa bắt đầu
        self._wifi_done = False  # đã xong (nối được hoặc bỏ cuộc)
        self._wifi_check = 0

        if CFG.ENABLE_WIFI:
            self._begin_wifi()
        else:
            self._wifi_done = True

    # --------------------------------------------------------
    # Bắt đầu quay số rồi TRẢ VỀ NGAY. Chờ WiFi ở đây nghĩa là màn hình đen
    # suốt 15 giây đầu và camera chưa nhìn thấy gì - trong khi WiFi chỉ dùng
    # để xem hình, còn báo động thì đi qua ESP32 nên không cần nó.
    def _begin_wifi(self):
        try:
            import network
            self.wlan = network.WLAN(network.STA_IF)
            self.wlan.active(True)
            if not self.wlan.isconnected():
                self.wlan.connect(CFG.WIFI_SSID, CFG.WIFI_PASSWORD)
            self._wifi_at = time.ticks_ms()
            print("[INFO] Đang kết nối WiFi ở chế độ nền:", CFG.WIFI_SSID)
        except Exception as e:
            print("[WARN] WiFi:", e)
            self._wifi_done = True

    # --------------------------------------------------------
    # Gọi trong vòng lặp chính, rất nhẹ. Khi nào có IP thì mở luồng xem hình.
    def _poll_wifi(self):
        if self._wifi_done or self.wlan is None:
            return
        now = time.ticks_ms()
        if time.ticks_diff(now, self._wifi_check) < 500:
            return
        self._wifi_check = now
        try:
            if self.wlan.isconnected():
                self.ip = self.wlan.ifconfig()[0]
                self._wifi_done = True
                print("[INFO] WiFi đã kết nối. IP =", self.ip)
                if CFG.ENABLE_STREAM:
                    self._start_server()
            elif time.ticks_diff(now, self._wifi_at) > CFG.WIFI_TIMEOUT_MS:
                self._wifi_done = True
                print("[WARN] Không vào được WiFi. Vẫn giám sát và vẫn báo")
                print("       được qua ESP32, chỉ là không xem hình từ xa.")
        except Exception as e:
            self._wifi_done = True
            print("[WARN] WiFi:", e)

    # --------------------------------------------------------
    def _start_server(self):
        try:
            import socket
            self.srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.srv.bind(("0.0.0.0", CFG.STREAM_PORT))
            self.srv.listen(2)
            # KHÔNG chặn: vòng lặp chính phải chạy tiếp dù không ai xem.
            self.srv.setblocking(False)
            print("[INFO] Xem trực tiếp tại http://%s:%d%s"
                  % (self.ip, CFG.STREAM_PORT, CFG.STREAM_PATH))
        except Exception as e:
            print("[WARN] Không mở được cổng xem hình:", e)
            self.srv = None

    # --------------------------------------------------------
    def _accept(self):
        if self.srv is None:
            return
        try:
            sock, addr = self.srv.accept()
        except Exception:
            return  # chưa ai gọi tới, chuyện bình thường

        try:
            sock.setblocking(False)
            # Đọc dòng yêu cầu cho xong để bên kia không kẹt, nhưng không cần
            # phân tích kỹ: cổng này chỉ phục vụ đúng một thứ.
            try:
                sock.recv(512)
            except Exception:
                pass

            sock.send(b"HTTP/1.1 200 OK\r\n"
                      b"Content-Type: multipart/x-mixed-replace; boundary=k230\r\n"
                      b"Cache-Control: no-cache\r\n"
                      b"Connection: close\r\n\r\n")
            self.clients.append(sock)
            print("[INFO] Có máy vào xem hình:", addr)
        except Exception as e:
            print("[WARN] Từ chối máy xem:", e)
            try:
                sock.close()
            except Exception:
                pass

    # --------------------------------------------------------
    def _push(self, jpg):
        con = []
        for sock in self.clients:
            try:
                sock.send(b"--k230\r\nContent-Type: image/jpeg\r\n"
                          b"Content-Length: %d\r\n\r\n" % len(jpg))
                sock.send(jpg)
                sock.send(b"\r\n")
                con.append(sock)
            except Exception:
                # Người xem đóng app hoặc đi khỏi vùng sóng. Dọn đi lặng lẽ.
                try:
                    sock.close()
                except Exception:
                    pass
        self.clients = con

    # --------------------------------------------------------
    # Gọi mỗi khung hình. Rất nhẹ khi không có ai xem.
    def poll(self, img_np, wh):
        self._poll_wifi()
        self._accept()
        if not self.clients:
            return
        self._n += 1
        if self._n % CFG.STREAM_EVERY != 0:
            return
        jpg = encode_jpeg(img_np, wh, CFG.STREAM_QUALITY)
        if jpg:
            self._push(jpg)

    # --------------------------------------------------------
    # Đẩy ảnh bằng chứng lên server relay, bằng PHIẾU dùng một lần.
    #
    # VÌ SAO DÙNG PHIẾU CHỨ K230 KHÔNG TỰ KÝ: khoá riêng của thiết bị nằm trên
    # con ESP32, không nằm ở đây. Truyền khoá sang đây cũng được, nhưng như vậy
    # là nhân bản một bí mật ra thêm một chỗ nữa mà chẳng được lợi gì.
    #
    # Thay vào đó ESP32 ký báo cáo ngã (nó có khoá), nhận về một phiếu sống 5
    # phút gắn với đúng một sự kiện, rồi đưa phiếu đó sang đây qua dây UART.
    # Nhặt được phiếu cũng chỉ đính được một tấm ảnh vào một cảnh báo đã xảy ra.
    #
    # Tự soạn HTTP POST bằng socket thay vì dùng thư viện, đúng tinh thần
    # "không dùng thư viện ngoài" của cả đề tài - và cũng vì bản CanMV không
    # chắc có sẵn urequests.
    def upload_snapshot(self, phieu):
        url = CFG.RELAY_URL or self.relay_url
        if not url or self.ip is None:
            return False

        jpg = self.anh_cho
        if not jpg:
            print("[WARN] Chưa có ảnh nào để đẩy lên.")
            return False

        try:
            import socket
            scheme, rest = url.split("://", 1)
            host = rest.split("/", 1)[0]
            port = 443 if scheme == "https" else 80
            if ":" in host:
                host, p = host.split(":", 1)
                port = int(p)

            path = "/api/snapshot?token=%s" % phieu

            addr = socket.getaddrinfo(host, port)[0][-1]
            sock = socket.socket()
            sock.settimeout(CFG.UPLOAD_TIMEOUT_S)
            sock.connect(addr)

            if scheme == "https":
                # Bản CanMV nào không có ssl thì báo rõ ràng chứ đừng im lặng
                # bỏ ảnh - người dùng sẽ tưởng hệ thống vẫn gửi ảnh bình thường.
                try:
                    import ssl
                    sock = ssl.wrap_socket(sock, server_hostname=host)
                except Exception as e:
                    print("[WARN] Bản CanMV này không mở được HTTPS:", e)
                    print("       Ảnh bằng chứng sẽ không gửi lên được.")
                    sock.close()
                    return False

            head = ("POST %s HTTP/1.1\r\nHost: %s\r\n"
                    "Content-Type: image/jpeg\r\nContent-Length: %d\r\n"
                    "Connection: close\r\n\r\n" % (path, host, len(jpg)))
            sock.write(head.encode())
            sock.write(jpg)

            resp = sock.read(64)
            sock.close()

            ok = resp is not None and b"200" in resp
            print("[INFO] Đẩy ảnh lên server:", "xong" if ok else resp)
            if ok:
                self.anh_cho = None
            return ok
        except Exception as e:
            print("[WARN] Đẩy ảnh thất bại:", e)
            return False

    # --------------------------------------------------------
    def deinit(self):
        for sock in self.clients:
            try:
                sock.close()
            except Exception:
                pass
        self.clients = []
        if self.srv is not None:
            try:
                self.srv.close()
            except Exception:
                pass
            self.srv = None


# ============================================================
# NGOẠI VI - gom mọi hành động cảnh báo vào một chỗ
# ============================================================
class Alerter:
    def __init__(self, net=None):
        self.uart = None
        self.net = net
        self._last_hb = 0
        self._rx = b""

        if CFG.ENABLE_UART:
            try:
                from machine import UART, FPIOA
                # Trên K230 phải gán chức năng cho chân trước khi mở UART.
                # Bỏ bước này thì UART vẫn mở được mà không có gì đi ra dây.
                fp = FPIOA()
                fp.set_function(CFG.UART_TX_PIN,
                                getattr(FPIOA, "UART%d_TXD" % CFG.UART_PORT))
                fp.set_function(CFG.UART_RX_PIN,
                                getattr(FPIOA, "UART%d_RXD" % CFG.UART_PORT))
                self.uart = UART(CFG.UART_PORT, CFG.UART_BAUD)
                global _uart_log
                _uart_log = self._send
                dlog("K230 chay ban: %s" % CFG.VERSION)
                print("[INFO] Đã mở UART%d %d baud (TX=%d, RX=%d)."
                      % (CFG.UART_PORT, CFG.UART_BAUD,
                         CFG.UART_TX_PIN, CFG.UART_RX_PIN))
            except Exception as e:
                print("[WARN] Không khởi tạo được UART:", e)

        if CFG.ENABLE_SNAPSHOT and not file_exists(CFG.SNAPSHOT_DIR):
            try:
                os.mkdir(CFG.SNAPSHOT_DIR)
            except Exception as e:
                print("[WARN] Không tạo được thư mục snapshot:", e)

    # --------------------------------------------------------
    # Ghi cho bằng hết. uart.write() trả về số byte THỰC ghi và có thể ít hơn
    # số đưa vào khi bộ đệm đầy (hay gặp sau một loạt dòng LOG); bỏ qua giá trị
    # đó thì dòng bị cắt cụt, ESP32 mất dấu xuống dòng.
    def _write_all(self, data, timeout_ms=5000):
        if not self.uart:
            return False
        if isinstance(data, str):
            data = data.encode()
        mv = memoryview(data)
        sent = 0
        t0 = time.ticks_ms()
        while sent < len(data):
            buoc = min(1024, len(data) - sent)
            try:
                n = self.uart.write(mv[sent:sent + buoc])
            except Exception as e:
                print("[WARN] uart:", e)
                return False
            if n is None:
                # Vài bản MicroPython trả None cho lần ghi chặn đã xong cả khối.
                sent += buoc
                t0 = time.ticks_ms()
            elif n > 0:
                sent += n
                t0 = time.ticks_ms()
            elif time.ticks_diff(time.ticks_ms(), t0) > timeout_ms:
                print("[WARN] Nghẽn UART, mới đẩy được %d/%d byte" % (sent, len(data)))
                return False
            else:
                time.sleep_ms(2)
        return True

    # --------------------------------------------------------
    def _send(self, line):
        self._write_all(line)

    # --------------------------------------------------------
    # Gọi đều đặn trong vòng lặp chính. Làm hai việc nhẹ:
    #   - báo "còn sống" sang ESP32 (im quá 30 giây là ESP32 coi như camera
    #     chết và báo lên app - im lặng mới là kiểu hỏng nguy hiểm nhất)
    #   - nhận cấu hình ESP32 gửi sang
    def poll(self, fps=0.0, ntracks=0):
        now = time.ticks_ms()
        if time.ticks_diff(now, self._last_hb) >= CFG.HEARTBEAT_MS:
            self._last_hb = now
            self._send("HB,%.1f,%d\n" % (fps, ntracks))
            if self.net is not None and self.net.ip:
                self._send("IP,%s,%d,%s\n"
                           % (self.net.ip, CFG.STREAM_PORT, CFG.STREAM_PATH))
        self._read_uart()

    # --------------------------------------------------------
    def _read_uart(self):
        if not self.uart:
            return
        try:
            n = self.uart.any()
            if not n:
                return
            self._rx += self.uart.read(n)
        except Exception:
            return

        while b"\n" in self._rx:
            line, self._rx = self._rx.split(b"\n", 1)
            try:
                self._on_line(line.decode().strip())
            except Exception:
                pass

        # Rác không có xuống dòng thì đừng để nó phình mãi.
        if len(self._rx) > 256:
            self._rx = b""

    # --------------------------------------------------------
    def _on_line(self, line):
        if self.net is None:
            return

        if line.startswith("CFG,"):
            parts = line.split(",")
            if len(parts) < 3:
                return
            self.net.home_id = parts[1]
            self.net.dev_id = parts[2]
            if len(parts) > 3:
                self.net.relay_url = parts[3]
            print("[INFO] Nhận cấu hình từ ESP32: nhà=%s máy=%s"
                  % (self.net.home_id, self.net.dev_id))
            return

        # SNAP,<mã sự kiện>,<phiếu tải ảnh>
        #
        # ESP32 vừa báo ngã lên server và xin được phiếu. Giờ mới đẩy ảnh -
        # đây là lúc server đã có sẵn sự kiện để gắn ảnh vào.
        if line.startswith("SNAP,"):
            parts = line.split(",")
            if len(parts) < 3:
                return
            print("[INFO] ESP32 cấp phiếu tải ảnh cho sự kiện", parts[1])
            self.net.upload_snapshot(parts[2])

    # --------------------------------------------------------
    def _encode_evidence(self, img_np, wh):
        jpg = grab_jpeg(img_np, wh, CFG.IMG_QUALITY)
        # Trả bộ đệm RGB888 tạm về ngay, đường hiển thị đang cần nó.
        gc.collect()
        if not jpg:
            return None
        dlog("anh: %d byte q=%d" % (len(jpg), CFG.IMG_QUALITY))
        return jpg

    # --------------------------------------------------------
    def fire(self, track_id, conf, img_np=None, wh=None):
        ts = time.ticks_ms()
        print("[ALARM] Phát hiện té ngã | track=%d conf=%.2f t=%d"
              % (track_id, conf, ts))

        # Báo sang ESP32 TRƯỚC MỌI THỨ KHÁC: dựng và lưu ảnh đều tốn thời gian,
        # mà đây mới là đường đưa tin tới người thân.
        self._send("FALL,%d,%.2f,%d\n" % (track_id, conf, ts))

        if CFG.ENABLE_EVIDENCE and img_np is not None and wh is not None:
            try:
                self._evidence(img_np, wh, ts)
            except Exception as e:
                # Mất ảnh chỉ là bất tiện; mất vòng lặp phát hiện mới nguy hiểm.
                print("[WARN] Bỏ qua ảnh bằng chứng:", e)
            gc.collect()

    def _evidence(self, img_np, wh, ts):
        jpg = self._encode_evidence(img_np, wh)
        if jpg:
            if CFG.ENABLE_SNAPSHOT:
                self._save(jpg, ts)
            # Giữ lại chờ phiếu CHỈ KHI có server relay. Không có relay mà
            # vẫn giữ thì đó là vài chục kilobyte nằm không tới lần ngã sau.
            if self.net is not None and (CFG.RELAY_URL or self.net.relay_url):
                self.net.anh_cho = jpg

    def _save(self, jpg, ts):
        try:
            path = "%s/fall_%d.jpg" % (CFG.SNAPSHOT_DIR, ts)
            with open(path, "wb") as f:
                f.write(jpg)
            print("[INFO] Đã lưu ảnh:", path)
        except Exception as e:
            print("[WARN] Lưu snapshot thất bại:", e)


# ============================================================
# TRACK - trạng thái của MỘT người
# ============================================================
class Track:
    NORMAL, SUSPECT, ALARM = 0, 1, 2
    STATE_NAME = {0: "OK", 1: "SUSPECT", 2: "FALL!"}

    def __init__(self, tid, box, now):
        self.id = tid
        self.box = box                # [x1,y1,x2,y2] trong không gian rgb888p
        self.votes = []               # cửa sổ trượt các phiếu 0/1
        self.cy_hist = []             # lịch sử tâm y để đo tốc độ rơi
        self.state = Track.NORMAL
        self.suspect_since = 0
        self.upright_since = 0
        self.last_seen = now
        self.last_alarm = -CFG.COOLDOWN_MS
        self.conf = 0.0

    def update(self, box, is_fall_cls, conf, now, frame_h):
        self.box = box
        self.last_seen = now
        self.conf = conf

        # --- tín hiệu 1: nhãn từ model ---
        signal = 1 if is_fall_cls else 0

        # --- tín hiệu 2 & 3: hình học ---
        if CFG.USE_GEOMETRY:
            w = max(1, box[2] - box[0])
            h = max(1, box[3] - box[1])
            aspect = w / h
            cy = (box[1] + box[3]) * 0.5

            self.cy_hist.append(cy)
            if len(self.cy_hist) > CFG.DROP_WINDOW:
                self.cy_hist.pop(0)

            lying = aspect > CFG.AR_LYING
            dropped = False
            if len(self.cy_hist) == CFG.DROP_WINDOW:
                dropped = (self.cy_hist[-1] - self.cy_hist[0]) > CFG.DROP_RATIO * frame_h

            if signal and lying:
                signal = 1          # model kêu + đang nằm -> chắc chắn
            elif dropped and lying:
                signal = 1          # rơi nhanh + nằm -> tính là nghi ngờ
            elif signal and not lying:
                signal = 0          # model kêu nhưng vẫn đứng -> nhiều khả năng nhiễu

        self.votes.append(signal)
        if len(self.votes) > CFG.VOTE_WINDOW:
            self.votes.pop(0)

        return self._step_state(now)

    def _step_state(self, now):
        fallen = (len(self.votes) >= CFG.VOTE_MIN and
                  sum(self.votes) >= CFG.VOTE_MIN)

        if self.state == Track.NORMAL:
            if fallen:
                self.state = Track.SUSPECT
                self.suspect_since = now

        elif self.state == Track.SUSPECT:
            if not fallen:
                self.state = Track.NORMAL      # đứng dậy nhanh -> chỉ là cúi/ngồi
            elif time.ticks_diff(now, self.suspect_since) >= CFG.CONFIRM_MS:
                if time.ticks_diff(now, self.last_alarm) >= CFG.COOLDOWN_MS:
                    self.state = Track.ALARM
                    self.last_alarm = now
                    self.upright_since = 0
                    return True                # -> kích hoạt cảnh báo
                else:
                    self.state = Track.NORMAL  # còn trong cooldown

        elif self.state == Track.ALARM:
            if not fallen:
                if self.upright_since == 0:
                    self.upright_since = now
                elif time.ticks_diff(now, self.upright_since) >= CFG.RECOVER_MS:
                    self.state = Track.NORMAL
                    print("[INFO] track=%d đã đứng dậy, huỷ báo động" % self.id)
            else:
                self.upright_since = 0

        return False


# ============================================================
# TRACKER - ghép detection giữa các frame bằng IoU
# ============================================================
class SimpleTracker:
    def __init__(self):
        self.tracks = []
        self.next_id = 1

    @staticmethod
    def _iou(a, b):
        x1 = max(a[0], b[0]); y1 = max(a[1], b[1])
        x2 = min(a[2], b[2]); y2 = min(a[3], b[3])
        iw = max(0, x2 - x1); ih = max(0, y2 - y1)
        inter = iw * ih
        if inter <= 0:
            return 0.0
        ua = (a[2]-a[0])*(a[3]-a[1]) + (b[2]-b[0])*(b[3]-b[1]) - inter
        return inter / ua if ua > 0 else 0.0

    def update(self, dets, now, frame_h):
        """dets: list (cls, conf, x1, y1, x2, y2). Trả về list track vừa báo động."""
        fired = []
        used = set()

        for cls, conf, x1, y1, x2, y2 in dets:
            box = [x1, y1, x2, y2]
            best, best_iou = None, CFG.IOU_MATCH_TH
            for t in self.tracks:
                if id(t) in used:
                    continue
                v = self._iou(t.box, box)
                if v > best_iou:
                    best, best_iou = t, v

            if best is None:
                best = Track(self.next_id, box, now)
                self.next_id += 1
                self.tracks.append(best)
            used.add(id(best))

            if best.update(box, cls == 0, conf, now, frame_h):
                fired.append(best)

        # dọn các track đã mất dấu
        self.tracks = [t for t in self.tracks
                       if time.ticks_diff(now, t.last_seen) < CFG.LOST_MS]
        return fired


# ============================================================
# ỨNG DỤNG AI
# ============================================================
class FallDetectionApp(AIBase):
    def __init__(self, kmodel_path, model_input_size, labels, anchors,
                 confidence_threshold=0.2, nms_threshold=0.5, nms_option=False,
                 strides=[8,16,32], rgb888p_size=[224,224],
                 display_size=[1920,1080], debug_mode=0):
        super().__init__(kmodel_path, model_input_size, rgb888p_size, debug_mode)
        self.kmodel_path = kmodel_path
        self.model_input_size = model_input_size
        self.labels = labels
        self.anchors = anchors
        self.strides = strides
        self.confidence_threshold = confidence_threshold
        self.nms_threshold = nms_threshold
        self.nms_option = nms_option
        self.rgb888p_size = [ALIGN_UP(rgb888p_size[0], 16), rgb888p_size[1]]
        self.display_size = [ALIGN_UP(display_size[0], 16), display_size[1]]
        self.debug_mode = debug_mode

        # Màu theo TRẠNG THÁI track (không phải theo nhãn từng frame)
        self.state_color = {
            Track.NORMAL:  (255,   0, 255,   0),   # xanh lá
            Track.SUSPECT: (255, 255, 200,   0),   # vàng
            Track.ALARM:   (255, 255,   0,   0),   # đỏ
        }

        self.ai2d = Ai2d(debug_mode)
        self.ai2d.set_ai2d_dtype(nn.ai2d_format.NCHW_FMT, nn.ai2d_format.NCHW_FMT,
                                 np.uint8, np.uint8)

    def config_preprocess(self, input_image_size=None):
        with ScopedTiming("set preprocess config", self.debug_mode > 0):
            ai2d_input_size = input_image_size if input_image_size else self.rgb888p_size
            top, bottom, left, right, _ = center_pad_param(self.rgb888p_size,
                                                           self.model_input_size)
            self.ai2d.pad([0,0,0,0, top, bottom, left, right], 0, [0,0,0])
            self.ai2d.resize(nn.interp_method.tf_bilinear, nn.interp_mode.half_pixel)
            self.ai2d.build([1,3,ai2d_input_size[1],ai2d_input_size[0]],
                            [1,3,self.model_input_size[1],self.model_input_size[0]])

    def postprocess(self, results):
        with ScopedTiming("postprocess", self.debug_mode > 0):
            return aicube.anchorbasedet_post_process(
                results[0], results[1], results[2],
                self.model_input_size, self.rgb888p_size, self.strides,
                len(self.labels), self.confidence_threshold, self.nms_threshold,
                self.anchors, self.nms_option)

    def draw_tracks(self, pl, tracks, fps):
        with ScopedTiming("display_draw", self.debug_mode > 0):
            pl.osd_img.clear()
            sx = self.display_size[0] / self.rgb888p_size[0]
            sy = self.display_size[1] / self.rgb888p_size[1]

            alarm_any = False
            for t in tracks:
                x1 = int(max(0, t.box[0] * sx))
                y1 = int(max(0, t.box[1] * sy))
                x2 = int(min(self.display_size[0] - 1, t.box[2] * sx))
                y2 = int(min(self.display_size[1] - 1, t.box[3] * sy))
                w, h = max(1, x2 - x1), max(1, y2 - y1)

                color = self.state_color.get(t.state, (255, 255, 255, 255))
                thick = 4 if t.state == Track.ALARM else 2
                if t.state == Track.ALARM:
                    alarm_any = True

                pl.osd_img.draw_rectangle(x1, y1, w, h, color=color, thickness=thick)
                txt = "#%d %s %.2f" % (t.id, Track.STATE_NAME[t.state], t.conf)
                pl.osd_img.draw_string_advanced(x1, max(0, y1 - 40), 32, txt,
                                                color=color)

            pl.osd_img.draw_string_advanced(10, 10, 28, "FPS %.1f" % fps,
                                            color=(255, 255, 255, 255))
            if alarm_any:
                pl.osd_img.draw_string_advanced(10, 50, 40, "CANH BAO TE NGA",
                                                color=(255, 255, 0, 0))


# ============================================================
# MAIN
# ============================================================
def main():
    if not file_exists(CFG.KMODEL_PATH):
        print("[ERROR] Không tìm thấy kmodel:", CFG.KMODEL_PATH)
        return

    pl = None
    fall_det = None
    alerter = None
    net = None

    try:
        # Mạng lên trước để lúc gửi nhịp tim đầu tiên sang ESP32 là đã có sẵn
        # địa chỉ xem hình - app thấy được khung video ngay, không phải chờ.
        net = NetLink()
        alerter = Alerter(net)
        tracker = SimpleTracker()

        print("[INFO] display_mode =", CFG.DISPLAY_MODE,
              "| display_size =", CFG.DISPLAY_SIZE)

        pl = PipeLine(rgb888p_size=CFG.RGB888P_SIZE,
                      display_mode=CFG.DISPLAY_MODE,
                      display_size=CFG.DISPLAY_SIZE)
        if CFG.SENSOR_ID is None:
            pl.create()
        else:
            pl.create(sensor_id=CFG.SENSOR_ID)

        disp = pl.get_display_size()
        print("[INFO] Độ phân giải màn hình thực tế:", disp)

        fall_det = FallDetectionApp(
            CFG.KMODEL_PATH,
            model_input_size=CFG.MODEL_INPUT_SIZE,
            labels=CFG.LABELS,
            anchors=CFG.ANCHORS,
            confidence_threshold=CFG.CONF_TH,
            nms_threshold=CFG.NMS_TH,
            nms_option=False,
            strides=CFG.STRIDES,
            rgb888p_size=CFG.RGB888P_SIZE,
            display_size=disp,
            debug_mode=CFG.DEBUG)
        fall_det.config_preprocess()

        frame_h = CFG.RGB888P_SIZE[1]
        n = 0
        fps = 0.0
        t_mark = time.ticks_ms()

        print("[INFO] Bắt đầu giám sát. Nhấn Stop trên IDE để dừng.")

        while True:
            img = pl.get_frame()
            if img is None:
                continue

            res = fall_det.run(img)
            now = time.ticks_ms()

            dets = []
            if res:
                for b in res:
                    dets.append((b[0], b[1], b[2], b[3], b[4], b[5]))

            for t in tracker.update(dets, now, frame_h):
                alerter.fire(t.id, t.conf, img, CFG.RGB888P_SIZE)

            # Đẩy hình cho máy đang xem và giữ nhịp với ESP32. Cả hai đều
            # không chặn: không ai xem thì gần như không tốn gì.
            net.poll(img, CFG.RGB888P_SIZE)
            alerter.poll(fps, len(tracker.tracks))

            fall_det.draw_tracks(pl, tracker.tracks, fps)
            pl.show_image()

            n += 1
            if n % CFG.FPS_EVERY == 0:
                dt = time.ticks_diff(time.ticks_ms(), t_mark)
                fps = CFG.FPS_EVERY * 1000.0 / dt if dt > 0 else 0.0
                t_mark = time.ticks_ms()
                print("[INFO] FPS=%.1f | tracks=%d" % (fps, len(tracker.tracks)))
            if n % CFG.GC_EVERY == 0:
                gc.collect()

    except KeyboardInterrupt:
        print("[INFO] Người dùng dừng chương trình.")
    except BaseException as e:
        print("[ERROR]", e)
        sys.print_exception(e)
    finally:
        # Phần bản demo gốc thiếu -> nguyên nhân phải reset board liên tục
        if fall_det is not None:
            try: fall_det.deinit()
            except Exception: pass
        if pl is not None:
            try: pl.destroy()
            except Exception: pass
        if net is not None:
            net.deinit()
        gc.collect()
        print("[INFO] Đã giải phóng tài nguyên.")


if __name__ == "__main__":
    main()
