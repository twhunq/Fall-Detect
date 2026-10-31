import 'package:flutter/material.dart';

import '../theme.dart';

/// Tiêu đề lớn đầu mỗi tab/trang.
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.text, {super.key, this.subtitle});

  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: AppText.largeTitle.copyWith(color: t.text)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(subtitle!,
                  style: TextStyle(fontSize: 15, height: 21 / 15, color: t.textSub)),
            ),
        ],
      ),
    );
  }
}

/// Nhóm trắng bo 14, các dòng ngăn bằng đường kẻ 1px; không đổ bóng.
class GroupSection extends StatelessWidget {
  const GroupSection({super.key, this.header, required this.children, this.footer});

  final String? header;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final kids = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) kids.add(Divider(height: 1, thickness: 1, indent: 16, color: t.line));
      kids.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(header!, style: AppText.section.copyWith(color: t.textSub)),
          ),
        Container(
          decoration: BoxDecoration(
              color: t.surface, borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(footer!,
                style: TextStyle(fontSize: 13, height: 18 / 13, color: t.textSub)),
          ),
      ],
    );
  }
}

/// Ô icon bo góc (nền trung tính hoặc theo trạng thái).
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.bg,
    this.fg,
    this.size = 38,
    this.radius = 10,
    this.iconSize = 22,
  });

  final IconData icon;
  final Color? bg;
  final Color? fg;
  final double size;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: bg ?? t.tile, borderRadius: BorderRadius.circular(radius)),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: fg ?? t.textStrong),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Dòng danh sách kiểu iOS: [leading] [tiêu đề/phụ đề] [giá trị] [trailing/chevron].
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.dot,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.accent = false,
    this.showChevron,
    this.minHeight,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;

  /// Chấm màu đặt trước phụ đề.
  final Color? dot;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool accent;
  final bool? showChevron;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final action = destructive || accent;
    final titleColor = destructive ? t.badText : (accent ? t.primary : t.text);
    final chevron = showChevron ?? (onTap != null && !action && trailing == null);
    final hasSub = subtitle != null;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(16, 0, chevron || trailing != null ? 12 : 16, 0),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      height: 22 / 16,
                      fontWeight: (hasSub || leading != null)
                          ? FontWeight.w600
                          : (action ? FontWeight.w500 : FontWeight.w400),
                      color: titleColor,
                    ),
                  ),
                  if (hasSub)
                    Row(
                      children: [
                        if (dot != null) ...[StatusDot(dot!), const SizedBox(width: 6)],
                        Flexible(
                          child: Text(
                            subtitle!,
                            style: AppText.rowSub.copyWith(color: subtitleColor ?? t.textSub),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (value != null && value!.isNotEmpty) ...[
            const SizedBox(width: 12),
            // Không dùng Flexible: tiêu đề chiếm phần còn lại, giá trị sát chevron.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                value!,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: t.textSub, fontFeatures: AppText.tabular),
              ),
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (chevron) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 22, color: t.chevron),
          ],
        ],
      ),
    );
    final h = minHeight ?? (hasSub || leading != null ? 64.0 : 52.0);
    final body = ConstrainedBox(constraints: BoxConstraints(minHeight: h), child: content);
    if (onTap == null) return body;
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: body),
    );
  }
}

/// Dòng có công tắc.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: subtitle == null ? 52 : 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 14, 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 16, height: 22 / 16, color: t.text)),
                  if (subtitle != null)
                    Text(subtitle!, style: AppText.rowSub.copyWith(color: t.textSub)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Dòng "nhãn — giá trị". [prominent] dùng cho trang chi tiết (chữ to hơn).
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(
    this.label,
    this.value, {
    super.key,
    this.dot,
    this.prominent = false,
    this.small = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? dot;
  final bool prominent;

  /// Giá trị cỡ nhỏ (dùng cho chuỗi dài như URL).
  final bool small;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fs = prominent ? 16.0 : 15.0;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: prominent ? 48 : 46),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: prominent ? 13 : 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Nhãn rộng theo nội dung (tối đa 190), giá trị lấp phần còn lại và căn phải sát mép.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(label,
                  style: TextStyle(
                      fontSize: fs, color: prominent ? t.textSub : t.textStrong)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (dot != null) ...[StatusDot(dot!), const SizedBox(width: 6)],
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: small ? 13 : (prominent ? 16 : fs),
                        fontWeight: prominent ? FontWeight.w500 : FontWeight.w400,
                        color: valueColor ?? (prominent ? t.text : t.textSub),
                        fontFeatures: AppText.tabular,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ô nhập nằm trong nhóm: nhãn nhỏ phía trên, ô nhập không viền.
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.label,
    required this.controller,
    this.fieldKey,
    this.enabled = true,
    this.obscure = false,
    this.keyboardType,
    this.hint,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final Key? fieldKey;
  final bool enabled;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.section.copyWith(color: t.textSub)),
          TextField(
            key: fieldKey,
            controller: controller,
            enabled: enabled,
            obscureText: obscure,
            autocorrect: false,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: TextStyle(fontSize: 16, color: enabled ? t.text : t.textSub),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              hintText: hint,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.only(top: 6, bottom: 4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thanh chọn phân đoạn kiểu iOS.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration:
          BoxDecoration(color: t.segTrack, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          for (final e in options.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: e.key == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: e.key == selected ? t.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: e.key == selected ? FontWeight.w600 : FontWeight.w500,
                        color: e.key == selected ? t.text : t.textStrong,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Khung trang con: nút quay lại kiểu iOS + nội dung cuộn được.
class SubPage extends StatelessWidget {
  const SubPage({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.backLabel = 'Quay lại',
    this.spacing = 22,
  });

  final String? title;
  final String? subtitle;
  final String backLabel;
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final items = <Widget>[
      if (title != null) LargeTitle(title!, subtitle: subtitle),
      ...children,
    ];
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.chevron_left_rounded, size: 28),
                  label: Text(backLabel, style: const TextStyle(fontSize: 17)),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.only(left: 0, right: 8),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: items.length,
                separatorBuilder: (_, _) => SizedBox(height: spacing),
                itemBuilder: (_, i) => items[i],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Khối thông báo trạng thái ngắn (cam/đỏ/xanh) không viền.
class InlineNote extends StatelessWidget {
  const InlineNote(this.text, {super.key, this.color, this.bg});

  final String text;
  final Color? color;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: bg ?? t.warnTint, borderRadius: BorderRadius.circular(12)),
      child: Text(text,
          style: TextStyle(fontSize: 14, height: 20 / 14, color: color ?? t.warnText)),
    );
  }
}

// ---- Định dạng thời gian ----

String _two(int v) => v.toString().padLeft(2, '0');

String fmtClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String fmtHm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String fmtDateTime(DateTime t) =>
    '${_two(t.day)}/${_two(t.month)}/${t.year} ${fmtClock(t)}';

/// "12 giây" / "5 phút" / "3 giờ" / "2 ngày" (không có chữ "trước").
String fmtSpan(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  if (s < 60) return '$s giây';
  if (s < 3600) return '${s ~/ 60} phút';
  if (s < 86400) return '${s ~/ 3600} giờ';
  return '${s ~/ 86400} ngày';
}

/// "vừa xong" / "x giây trước" / "x phút trước" / "x giờ trước" / "x ngày trước".
String fmtRelative(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inSeconds < 5) return 'vừa xong';
  return '${fmtSpan(d)} trước';
}

String fmtAge(DateTime? t, DateTime now) =>
    t == null ? 'chưa có' : fmtRelative(t, now);

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

const List<String> _weekdays = [
  'Thứ Hai',
  'Thứ Ba',
  'Thứ Tư',
  'Thứ Năm',
  'Thứ Sáu',
  'Thứ Bảy',
  'Chủ nhật',
];

/// "Hôm nay" / "Hôm qua" / "Thứ Ba, 28/10".
String fmtDayHeader(DateTime t, DateTime now) {
  final diff = _day(now).difference(_day(t)).inDays;
  if (diff == 0) return 'Hôm nay';
  if (diff == 1) return 'Hôm qua';
  return '${_weekdays[t.weekday - 1]}, ${_two(t.day)}/${_two(t.month)}';
}

/// "Hôm nay, 14:32".
String fmtDayHm(DateTime t, DateTime now) => '${fmtDayHeader(t, now)}, ${fmtHm(t)}';

String fmtDuration(int seconds) {
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (d > 0) return '$d ngày $h giờ';
  if (h > 0) return '$h giờ $m phút';
  if (m > 0) return '$m phút $s giây';
  return '$s giây';
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
