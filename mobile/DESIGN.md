# Hệ thống thị giác — Báo Ngã IoT

Tối giản, kiểu iOS sạch, xanh dương + trắng. Chỉ hiện thứ người nhà cần; thông số kỹ thuật nằm ở Cài đặt › Chẩn đoán và mục "Thông tin kỹ thuật" của từng sự cố.

## Nguyên tắc
- Không lồng card trong card. Nhóm = Container trắng bo 14, các dòng ngăn bằng đường kẻ 1px (thụt 16). Không đổ bóng.
- Bo góc: nhóm/khung camera 14, nút và ô nhập 12–14, tile icon 10 (hero 16).
- Vùng chạm tối thiểu 44–48 px. Icon Material `*_rounded`/outlined, không emoji.
- Mọi chữ tiếng Việt có dấu; thuật ngữ kỹ thuật chỉ ở trang Chẩn đoán.

## Font
Be Vietnam Pro (OFL) gói trong `assets/fonts/` (400/500/600/700/800), family `BeVietnamPro`. Số liệu dùng `FontFeature.tabularFigures()`.

## Màu (token trong `lib/ui/theme.dart`, truy cập `context.tokens`)
| Token | Sáng | Tối |
|---|---|---|
| bg | `#F4F6FA` | `#0B0F17` |
| surface | `#FFFFFF` | `#161B26` |
| text / textSub / textStrong | `#0E1525` / `#586174` / `#33405A` | `#E8ECF3` / `#9AA4B6` / `#C3CBDA` |
| line | `#E7EAF0` | `#262D3B` |
| primary (pressed, tint) | `#1660D8` (`#0F4FB8`, `#E4EEFD`) | `#5B9BF5` |
| ok (text, tint) | `#16A34A` (`#13804A`, `#E7F6EE`) | sáng hơn |
| warn (text, tint) | `#D97706` (`#B25E09`, `#FFF3E0`) | sáng hơn |
| bad (tint) | `#C2281E` (`#FDECEC`) | sáng hơn |
| chevron / tile | `#A3ABBA` / `#EEF2F8` | `#677088` / `#212838` |
| nền báo động | `#B42318` (cố định) | |

## Chữ
Tiêu đề lớn 30/36 w700 (-0.6); hero 28 w700; tiêu đề nhóm 13 w600 chữ phụ; dòng 16 w600 + phụ đề 14; nhãn tab 11 w600. Định nghĩa trong `AppText`.

## Widget dùng chung (`lib/ui/widgets/common.dart`)
`LargeTitle`, `GroupSection`, `ListRow`, `SwitchRow`, `KeyValueRow`, `FieldRow`, `IconTile`, `StatusDot`, `SegmentedControl`, `SubPage` (trang con có nút quay lại), `InlineNote`; định dạng `fmtRelative`, `fmtSpan`, `fmtDayHeader`, `fmtDayHm`, `fmtHm`, `fmtDateTime`. Nhãn sự cố/icon/màu: `widgets/incident_ui.dart`.

## Màn hình
- Tab: Tổng quan / Lịch sử / Cài đặt (NavigationBar nền trắng, viền trên hairline, mục chọn màu xanh).
- Tổng quan: hero theo trạng thái (báo động › không cử động › mất tín hiệu › đang kết nối › an toàn), khung camera 16:9, nhóm thiết bị, sự cố gần nhất.
- Báo động: nền đỏ toàn màn hình, 2 nút (Gọi cấp cứu 115, Đã kiểm tra tắt chuông).
- Cài đặt: danh sách nhóm, mỗi dòng mở trang con (`lib/ui/settings/`), trang Chẩn đoán ở `lib/ui/diagnostics_page.dart`.
