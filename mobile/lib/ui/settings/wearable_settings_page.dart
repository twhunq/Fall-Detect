import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/presence.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/wifi_section.dart';

/// Trạng thái gọn của vòng đeo và cài đặt Wi-Fi cho vòng.
class WearableSettingsPage extends StatelessWidget {
  const WearableSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final t = context.tokens;
    final now = DateTime.now();
    final presence = c.wearablePresence;
    final last = c.wearableLastSeen;
    final String state;
    final Color dot;
    switch (presence) {
      case WearablePresence.online:
        state = 'Đang kết nối';
        dot = t.ok;
      case WearablePresence.offline:
        state = 'Mất kết nối';
        dot = t.warn;
      case WearablePresence.unknown:
        state = 'Chưa có dữ liệu';
        dot = t.chevron;
    }
    final pct = c.batteryPercent;
    final battery = c.onUsbPower ? 'Cắm nguồn' : (pct == null ? 'Chưa rõ' : '$pct%');
    return SubPage(
      title: 'Vòng đeo',
      children: [
        GroupSection(children: [
          KeyValueRow('Trạng thái', state, dot: dot, prominent: true),
          KeyValueRow('Nhận tin lần cuối', last == null ? 'Chưa có' : fmtRelative(last, now),
              prominent: true),
          KeyValueRow('Pin', battery,
              prominent: true,
              valueColor: c.wearable?.batteryLow == true ? t.badText : null),
        ]),
        if (presence == WearablePresence.unknown)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Chưa nhận được dữ liệu? Nhập địa chỉ ở Cài đặt › Chẩn đoán › Kết nối thủ công.',
              style: TextStyle(fontSize: 13, height: 18 / 13, color: t.textSub),
            ),
          ),
        const WifiSection(),
      ],
    );
  }
}
