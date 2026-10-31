import 'package:flutter/material.dart';

import '../../core/fusion/alert_models.dart';
import '../theme.dart';

/// Tên nguồn phát hiện: "Vòng đeo" / "Camera" / "Vòng đeo và camera".
String incidentSource(AlertIncident i) {
  final w = i.origins.contains(AlertOrigin.wearable);
  final c = i.origins.contains(AlertOrigin.camera);
  if (w && c) return 'Vòng đeo và camera';
  if (c) return 'Camera';
  return 'Vòng đeo';
}

/// Tiêu đề ngắn của sự cố.
String incidentTitle(AlertIncident i) {
  switch (i.kind) {
    case AlertKind.fall:
      return 'Ngã';
    case AlertKind.inactive:
      final m = i.stillMinutes?.round();
      return m == null || m <= 0 ? 'Không cử động' : 'Không cử động $m phút';
    case AlertKind.resumed:
      return 'Đã cử động lại';
  }
}

IconData incidentIcon(AlertKind k) {
  switch (k) {
    case AlertKind.fall:
      return Icons.warning_amber_rounded;
    case AlertKind.inactive:
      return Icons.timer_outlined;
    case AlertKind.resumed:
      return Icons.directions_walk_rounded;
  }
}

({Color bg, Color fg}) incidentColors(BuildContext context, AlertKind k) {
  final t = context.tokens;
  switch (k) {
    case AlertKind.fall:
      return (bg: t.badTint, fg: t.bad);
    case AlertKind.inactive:
      return (bg: t.warnTint, fg: t.warnText);
    case AlertKind.resumed:
      return (bg: t.okTint, fg: t.okText);
  }
}

/// Nhãn hoạt động ngắn ("Đang đi lại"...) hoặc null nếu không hiển thị.
String? activityLabel(String? a) {
  switch (a) {
    case 'di_bo':
      return 'Đang đi lại';
    case 'dung':
      return 'Đang đứng';
    case 'ngoi':
      return 'Đang ngồi';
    case 'nam':
      return 'Đang nằm';
    default:
      return null;
  }
}

/// Nhãn hoạt động cho trang chẩn đoán.
String activityShort(String? a) {
  switch (a) {
    case 'di_bo':
      return 'Đi bộ';
    case 'dung':
      return 'Đứng';
    case 'ngoi':
      return 'Ngồi';
    case 'nam':
      return 'Nằm';
    case 'nga':
      return 'Ngã';
    default:
      return a == null || a.isEmpty ? 'Không rõ' : a;
  }
}
