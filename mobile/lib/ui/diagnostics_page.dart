import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/wearable_lan_service.dart';
import '../state/app_controller.dart';
import 'settings/manual_connection_page.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/incident_ui.dart';

/// Thông tin kỹ thuật để kiểm tra khi thiết bị gặp sự cố.
class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final t = context.tokens;
    final now = DateTime.now();
    final h = c.health;
    final s = c.wearable;
    final info = c.cameraInfo;

    KeyValueRow channel(String label, bool on, {String off = 'Không hoạt động', String onText = 'Hoạt động'}) =>
        KeyValueRow(label, on ? onText : off, dot: on ? t.ok : t.chevron);

    return SubPage(
      title: 'Chẩn đoán',
      subtitle: 'Thông tin kỹ thuật để kiểm tra khi thiết bị gặp sự cố.',
      backLabel: 'Cài đặt',
      children: [
        GroupSection(header: 'Đường nhận cảnh báo', children: [
          channel('Wi-Fi nội bộ (UDP)', h.udp),
          channel('Cloud (Firebase)', h.cloud),
          channel('Hỏi trực tiếp vòng đeo (LAN)', h.lan),
          channel('Bluetooth camera', h.ble, off: 'Không kết nối', onText: 'Đã kết nối'),
        ]),
        GroupSection(
          header: 'Vòng đeo',
          children: s == null
              ? const [KeyValueRow('Trạng thái', 'Chưa có dữ liệu')]
              : [
                  KeyValueRow('Cảm biến chuyển động', s.imu ? 'Bình thường' : 'Lỗi',
                      valueColor: s.imu ? null : t.badText),
                  KeyValueRow('Mô hình AI', s.model ? 'Sẵn sàng' : 'Chưa nạp',
                      valueColor: s.model ? null : t.badText),
                  KeyValueRow('Hiệu chuẩn', _cal(s.cal)),
                  KeyValueRow('Hoạt động · độ tin cậy',
                      '${activityShort(s.activity)} · ${(s.confidence * 100).toStringAsFixed(0)}%'),
                  KeyValueRow(
                      'Điện áp pin',
                      s.batteryMv < 2000
                          ? 'Cắm nguồn'
                          : '${(s.batteryMv / 1000).toStringAsFixed(2).replaceAll('.', ',')} V',
                      valueColor: s.batteryLow ? t.badText : null),
                  KeyValueRow('Sóng Wi-Fi', s.rssi == 0 ? 'Không có' : '${s.rssi} dBm'),
                  KeyValueRow('Cloud', _cloud(s)),
                  KeyValueRow('Địa chỉ IP', s.ip.isEmpty ? 'Chưa biết' : s.ip),
                  KeyValueRow('Đã chạy', fmtDuration(s.uptime)),
                  KeyValueRow('Nguồn dữ liệu',
                      '${s.source == 'cloud' ? 'Cloud' : 'LAN'} · ${fmtAge(c.lastStatusAt, now)}'),
                  KeyValueRow('Mã thiết bị', c.settings.deviceId),
                ],
        ),
        GroupSection(header: 'Camera', children: [
          KeyValueRow('Xác thực', c.cameraAuthenticated ? 'Đã xác thực' : 'Chưa xác thực'),
          KeyValueRow('Tín hiệu gần nhất', fmtAge(c.lastAlive, now)),
          KeyValueRow(
              'Wi-Fi camera',
              c.cameraWifi == null
                  ? 'Chưa rõ'
                  : (c.cameraWifi! ? 'Đã kết nối' : 'Chưa kết nối')),
          KeyValueRow('Luồng hình', info?.streamUri?.toString() ?? 'Chưa biết', small: true),
          KeyValueRow(
              'Cảnh báo cuối',
              c.lastCameraAlertAt == null
                  ? 'Chưa có'
                  : '${fmtClock(c.lastCameraAlertAt!)} (${c.lastCameraAlertPercent?.toStringAsFixed(0)}%)'),
        ]),
        GroupSection(header: 'Kết nối thủ công', children: [
          ListRow(
            title: 'Địa chỉ vòng đeo và mật khẩu',
            onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const ManualConnectionPage())),
          ),
        ]),
      ],
    );
  }

  static String _cal(String c) {
    switch (c) {
      case 'run':
        return 'Đang hiệu chuẩn';
      case 'ok':
        return 'Đã xong';
      default:
        return 'Chưa hiệu chuẩn';
    }
  }

  static String _cloud(WearableStatus s) {
    switch (s.cloud) {
      case 'ok':
        return 'Đã kết nối';
      case 'wait':
        return 'Đang chờ';
      case 'auth':
        return 'Lỗi xác thực';
      case 'off':
        return 'Tắt';
      default:
        return s.source == 'cloud' ? 'Đã kết nối' : 'Không rõ';
    }
  }
}
