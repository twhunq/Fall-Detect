import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/wearable_lan_service.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/wifi_section.dart';

const Map<String, String> kClassNames = {
  'di_bo': 'Đang đi bộ',
  'dung': 'Đang đứng',
  'nam': 'Đang nằm',
  'nga': 'Ngã',
  'ngoi': 'Đang ngồi',
};

class WearableTab extends StatelessWidget {
  const WearableTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final s = c.wearable;
    final colors = context.statusColors;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (s != null && s.alarmActive)
          const StatusBanner(
              text: 'PHÁT HIỆN NGÃ', icon: Icons.warning_amber_rounded, color: Color(0xFFDC2626))
        else if (s != null && s.inactive)
          StatusBanner(text: 'BẤT ĐỘNG', icon: Icons.hourglass_bottom, color: colors.warn),
        if (s != null && (s.alarmActive || s.inactive)) const SizedBox(height: 10),
        _StatusCard(controller: c, status: s),
        const SizedBox(height: 12),
        const _ConnectionCard(),
        const SizedBox(height: 12),
        const WifiSection(),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller, required this.status});

  final AppController controller;
  final WearableStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final colors = context.statusColors;
    if (s == null) {
      return SectionCard(
        title: 'Trạng thái trực tiếp',
        child: Text(
          'Chưa nhận được dữ liệu từ vòng đeo. Kiểm tra Wi-Fi/đăng nhập hoặc nhập địa chỉ vòng đeo bên dưới.',
          style: TextStyle(color: colors.muted),
        ),
      );
    }
    final activity = kClassNames[s.activity] ?? (s.activity ?? 'Không rõ');
    final String battery;
    if (s.batteryMv < 2000) {
      battery = 'Đang cắm USB / không có pin';
    } else {
      battery = '${(s.batteryMv / 1000).toStringAsFixed(2)} V${s.batteryLow ? ' (pin yếu)' : ''}';
    }
    final now = DateTime.now();
    final source = s.source == 'cloud' ? 'Cloud' : 'LAN';
    return SectionCard(
      title: 'Trạng thái trực tiếp',
      child: Column(
        children: [
          InfoRow('Hoạt động', '$activity (${(s.confidence * 100).toStringAsFixed(0)}%)',
              color: s.activity == 'nga' ? colors.bad : null),
          InfoRow('Đứng yên', '${s.stillSec} giây', color: s.inactive ? colors.warn : null),
          InfoRow('Pin', battery, color: s.batteryLow ? colors.bad : null),
          InfoRow('IMU', s.imu ? 'Hoạt động' : 'Lỗi', color: s.imu ? colors.ok : colors.bad),
          InfoRow('Mô hình', s.model ? 'Sẵn sàng' : 'Chưa nạp',
              color: s.model ? colors.ok : colors.bad),
          InfoRow('Hiệu chuẩn', _cal(s.cal)),
          InfoRow('Wi-Fi RSSI', s.rssi == 0 ? 'Không có' : '${s.rssi} dBm'),
          InfoRow('Cloud', _cloud(s)),
          InfoRow('Địa chỉ IP', s.ip.isEmpty ? 'Chưa biết' : s.ip),
          InfoRow('Thời gian chạy', fmtDuration(s.uptime)),
          InfoRow('Nguồn dữ liệu', '$source · ${fmtAge(controller.lastStatusAt, now)}'),
        ],
      ),
    );
  }

  static String _cal(String c) {
    switch (c) {
      case 'run':
        return 'Đang hiệu chuẩn';
      case 'ok':
        return 'Đã hiệu chuẩn';
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

class _ConnectionCard extends StatefulWidget {
  const _ConnectionCard();

  @override
  State<_ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<_ConnectionCard> {
  late final TextEditingController _url;
  late final TextEditingController _pass;

  @override
  void initState() {
    super.initState();
    final c = context.read<AppController>();
    _url = TextEditingController(text: c.settings.wearableBaseUrl);
    _pass = TextEditingController(text: c.settings.wearablePassword);
  }

  @override
  void dispose() {
    _url.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final learned = c.backend.wearableBaseUrl;
    return SectionCard(
      title: 'Kết nối',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('wearableUrl'),
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Địa chỉ vòng đeo',
              hintText: learned.isEmpty ? 'http://baonga.local hoặc 192.168.x.x' : learned,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('wearablePassword'),
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Mật khẩu trang thiết bị (nếu có)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () async {
                  await c.saveWearableConnection(_url.text, _pass.text);
                  if (context.mounted) showSnack(context, 'Đã lưu.');
                },
                child: const Text('Lưu'),
              ),
              OutlinedButton(
                onPressed: () => _url.text = 'http://baonga.local',
                child: const Text('baonga.local'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
