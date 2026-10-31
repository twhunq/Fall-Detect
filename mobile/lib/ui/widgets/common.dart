import 'package:flutter/material.dart';

import '../theme.dart';

/// Thẻ có tiêu đề dùng chung trong các tab.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// Dòng "nhãn: giá trị".
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final muted = context.statusColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: muted)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontWeight: FontWeight.w500, color: color)),
          ),
        ],
      ),
    );
  }
}

/// Banner màu (đỏ/cam/xanh) với chữ đậm.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, color: color), const SizedBox(width: 10)],
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

String fmtClock(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

String fmtDateTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${fmtClock(t)}';
}

String fmtAge(DateTime? t, DateTime now) {
  if (t == null) return 'chưa có';
  final s = now.difference(t).inSeconds;
  if (s < 0) return 'vừa xong';
  if (s < 60) return '$s giây trước';
  if (s < 3600) return '${s ~/ 60} phút trước';
  return '${s ~/ 3600} giờ trước';
}

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
