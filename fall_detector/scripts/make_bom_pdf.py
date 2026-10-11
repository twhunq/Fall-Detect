"""Generate docs/danh_sach_linh_kien.pdf (Vietnamese component list).

Needs reportlab; uses Windows Arial for Vietnamese glyphs.
"""
import os

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (Image, KeepTogether, Paragraph, SimpleDocTemplate, Spacer,
                                Table, TableStyle)

PRJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PRJ, "docs", "danh_sach_linh_kien.pdf")
FONTS = "C:/Windows/Fonts/"
pdfmetrics.registerFont(TTFont("Arial", FONTS + "arial.ttf"))
pdfmetrics.registerFont(TTFont("Arial-Bold", FONTS + "arialbd.ttf"))
pdfmetrics.registerFont(TTFont("Arial-Italic", FONTS + "ariali.ttf"))
pdfmetrics.registerFontFamily("Arial", normal="Arial", bold="Arial-Bold", italic="Arial-Italic")

INK = colors.HexColor("#1f2933")
MUTED = colors.HexColor("#5f6b76")
ACCENT = colors.HexColor("#1d6f5f")
HEAD_BG = colors.HexColor("#e4efec")
ZEBRA = colors.HexColor("#f6f8f8")
RULE = colors.HexColor("#c9d3d1")

title = ParagraphStyle("title", fontName="Arial-Bold", fontSize=18, leading=22, textColor=INK)
sub = ParagraphStyle("sub", fontName="Arial", fontSize=10, leading=14, textColor=MUTED)
h2 = ParagraphStyle("h2", fontName="Arial-Bold", fontSize=12, leading=15, textColor=ACCENT,
                    spaceBefore=10, spaceAfter=5)
cell = ParagraphStyle("cell", fontName="Arial", fontSize=8.8, leading=11, textColor=INK)
cellc = ParagraphStyle("cellc", parent=cell, alignment=TA_CENTER)
head = ParagraphStyle("head", fontName="Arial-Bold", fontSize=8.8, leading=11, textColor=INK)
headc = ParagraphStyle("headc", parent=head, alignment=TA_CENTER)
note = ParagraphStyle("note", fontName="Arial", fontSize=9, leading=12.5, textColor=INK,
                      leftIndent=10, bulletIndent=0)
caption = ParagraphStyle("caption", parent=sub, fontSize=8.5, alignment=TA_CENTER)

HEADER = ["STT", "Ký hiệu", "Linh kiện / thông số", "SL", "Chức năng trong mạch", "Ghi chú khi mua / lắp"]
WIDTHS = [9 * mm, 16 * mm, 44 * mm, 9 * mm, 50 * mm, 52 * mm]

SECTIONS = [
    ("1. Linh kiện chính", [
        ("U1", "ESP32-S3 Super Mini", "1", "Vi điều khiển, Wi-Fi/BLE, xử lý thuật toán té ngã",
         "Cắm qua 2 hàng rào cái 1×9 chân"),
        ("U2", "Module GY-521 (MPU6050)", "1", "Cảm biến gia tốc + con quay 6 trục, giao tiếp I2C (0x68)",
         "Cắm qua hàng rào cái 1×8 chân; VCC ở trên cùng, thân module nằm về phía phải (xa ESP32)"),
        ("U3", "Module cảm biến chạm TTP223", "1", "Nút chạm hủy báo động / gọi SOS",
         "Kiểm tra thứ tự chân GND – I/O – VCC"),
        ("BZ1", "Còi chip chủ động 3 V, Ø12 mm, chân cách 7.6 mm", "1", "Phát âm báo khi phát hiện té ngã",
         "Chân (+) cắm lỗ vuông có dấu +"),
        ("D3", "LED 5 mm màu đỏ", "1", "Đèn báo trạng thái",
         "Chân dài (+) vào lỗ tròn, chân ngắn vào lỗ vuông"),
    ]),
    ("2. Điện trở (1/4 W, chân cắm)", [
        ("R1", "1 kΩ (nâu–đen–đỏ–nhũ)", "1", "Hạn dòng chân B của transistor Q1", ""),
        ("R2", "10 kΩ (nâu–đen–cam–nhũ)", "1", "Giữ Q1 tắt khi ESP32 khởi động, còi không kêu bậy", ""),
        ("R3", "330 Ω (cam–cam–nâu–nhũ)", "1", "Hạn dòng LED (~4 mA)", ""),
        ("R4, R5", "100 kΩ (nâu–đen–vàng–nhũ)", "2", "Cầu phân áp đo điện áp pin (GPIO1)", ""),
    ]),
    ("3. Tụ điện", [
        ("C1", "Tụ hóa 100 µF 16 V (Ø5–6.3 mm, chân cách 2.5 mm)", "1",
         "Giữ ổn định nguồn 3V3 khi còi kêu", "Có cực: chân dài (+) vào lỗ vuông"),
        ("C2, C3, C4", "Tụ gốm 100 nF (mã 104)", "3",
         "Lọc nhiễu nguồn MPU6050, TTP223 và chân đo pin", "Chân cách 5 mm (bẻ chân nếu loại 2.54 mm)"),
    ]),
    ("4. Diode và transistor", [
        ("D1", "Diode 1N4148", "1", "Dập điện áp ngược từ còi", "Vạch đen = K, vào lỗ vuông có chữ K"),
        ("D2", "Diode Schottky 1N5817 (hoặc 1N5819)", "1", "Chặn 5V từ cổng USB chảy ngược vào pin",
         "1N5817 sụt áp thấp hơn. Vạch trắng = K, vào lỗ vuông có chữ K"),
        ("Q1", "Transistor NPN S8050 (TO-92)", "1", "Công tắc bật/tắt còi",
         "Chân E–B–C. Thay được bằng 2N2222 / PN2222A; không dùng C1815"),
    ]),
    ("5. Nguồn và kết nối", [
        ("J1", "Đầu JST PH 2.0 mm, 2 chân, loại đứng", "1", "Cắm dây pin từ OUT+/OUT− của TP4056",
         "Chân (+) bên trái, có in lụa + −"),
        ("SW1", "Công tắc gạt SS12D00 (3 chân)", "1", "Công tắc nguồn", "Lỗ oval 1.4×1.0 mm, nhận chân 2.0 hoặc 2.54 mm"),
        ("–", "Module sạc TP4056 Type-C có mạch bảo vệ", "1", "Sạc pin, chống sạc quá / xả cạn",
         "Nằm ngoài PCB"),
        ("–", "Pin Li-Po 3.7 V, 500–1000 mAh", "1", "Nguồn cho mạch", "Nằm ngoài PCB"),
    ]),
    ("6. Phụ kiện lắp ráp", [
        ("–", "Hàng rào cái 2.54 mm 1×9 chân", "2", "Đế cắm ESP32-S3 Super Mini",
         "Có thể mua loại 1×40 rồi bẻ"),
        ("–", "Hàng rào cái 2.54 mm 1×8 chân", "1", "Đế cắm module GY-521", ""),
        ("–", "Hàng rào cái 2.54 mm 1×3 chân", "1", "Đế cắm module TTP223", ""),
        ("H1–H4", "Ốc M3 + trụ đồng", "4", "Bắt vào 4 lỗ góc board", "Lỗ Ø3.2 mm"),
    ]),
]


def section_table(rows, start):
    data = [[Paragraph(h, headc if i in (0, 3) else head) for i, h in enumerate(HEADER)]]
    for n, (ref, part, qty, func, tip) in enumerate(rows, start):
        data.append([Paragraph(str(n), cellc), Paragraph(f"<b>{ref}</b>", cell), Paragraph(part, cell),
                     Paragraph(qty, cellc), Paragraph(func, cell), Paragraph(tip, cell)])
    t = Table(data, colWidths=WIDTHS, repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), HEAD_BG),
        ("LINEBELOW", (0, 0), (-1, 0), 0.8, ACCENT),
        ("LINEBELOW", (0, 1), (-1, -1), 0.3, RULE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 3.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
    ]
    for r in range(2, len(data), 2):
        style.append(("BACKGROUND", (0, r), (-1, r), ZEBRA))
    t.setStyle(TableStyle(style))
    return t


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Arial", 8)
    canvas.setFillColor(MUTED)
    canvas.drawString(15 * mm, 10 * mm, "Mạch phát hiện té ngã – ESP32-S3 SuperMini + MPU6050 – Rev 1.1")
    canvas.drawRightString(A4[0] - 15 * mm, 10 * mm, f"Trang {doc.page}")
    canvas.restoreState()


def main():
    doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=15 * mm, rightMargin=15 * mm,
                            topMargin=14 * mm, bottomMargin=18 * mm,
                            title="Danh sách linh kiện – Mạch phát hiện té ngã", author="fall_detector")
    story = [
        Paragraph("Danh sách linh kiện", title),
        Spacer(1, 2),
        Paragraph("Mạch phát hiện té ngã – ESP32-S3 SuperMini + MPU6050 · PCB 2 lớp 60 × 50 mm · "
                  "toàn bộ linh kiện chân cắm xuyên lỗ · Rev 1.1 · 26/09/2026", sub),
        Spacer(1, 8),
    ]
    img = os.path.join(PRJ, "docs", "pcb_iso_3d.png")
    if os.path.exists(img):
        story += [Image(img, width=105 * mm, height=105 * mm * 1100 / 1400),
                  Paragraph("Ảnh render 3D của PCB (các module cắm rời chưa hiển thị)", caption),
                  Spacer(1, 4)]

    n = 1
    for heading, rows in SECTIONS:
        story.append(KeepTogether([Paragraph(heading, h2), section_table(rows, n)]))
        n += len(rows)

    notes = [
        "Linh kiện đều phổ biến tại Việt Nam: Hshop, ICDayRoi, Shopee/Lazada, chợ Nhật Tảo (TP.HCM), chợ Trời (Hà Nội).",
        "Nên mua dư mỗi loại điện trở, tụ, diode vài con (thường bán theo bịch 10–100 con).",
        "Linh kiện có cực tính: C1, D1, D2, D3, Q1, BZ1, J1 – đối chiếu ký hiệu in lụa trên PCB trước khi hàn.",
        "Kiểm tra thứ tự chân ESP32-S3 SuperMini và TTP223 với module thực tế; tên chân được in lụa cạnh lỗ cắm.",
        "Cắm module theo tên chân in lụa (VCC vào VCC…), không theo hình dạng khung. TTP223: hai đầu VCC/GND "
        "đảo nhau tùy hãng, cắm ngược sẽ đảo cực nguồn.",
        "Khi nạp code qua cổng USB-C của SuperMini, pin không được sạc – sạc qua cổng USB của module TP4056.",
    ]
    story.append(KeepTogether([Paragraph("Lưu ý", h2)] +
                              [Paragraph(s, note, bulletText="•") for s in notes]))
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
