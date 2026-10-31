import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_controller.dart';
import '../widgets/common.dart';

/// Nhập tay địa chỉ/mật khẩu vòng đeo và mã thiết bị/mã nhà.
class ManualConnectionPage extends StatefulWidget {
  const ManualConnectionPage({super.key});

  @override
  State<ManualConnectionPage> createState() => _ManualConnectionPageState();
}

class _ManualConnectionPageState extends State<ManualConnectionPage> {
  late final TextEditingController _url;
  late final TextEditingController _pass;
  late final TextEditingController _deviceId;
  late final TextEditingController _homeId;

  @override
  void initState() {
    super.initState();
    final c = context.read<AppController>();
    _url = TextEditingController(text: c.settings.wearableBaseUrl);
    _pass = TextEditingController(text: c.settings.wearablePassword);
    _deviceId = TextEditingController(text: c.settings.deviceId);
    _homeId = TextEditingController(text: c.settings.homeId);
  }

  @override
  void dispose() {
    _url.dispose();
    _pass.dispose();
    _deviceId.dispose();
    _homeId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final learned = c.backend.wearableBaseUrl;
    return SubPage(
      title: 'Kết nối thủ công',
      subtitle: 'Chỉ cần khi ứng dụng không tự tìm thấy vòng đeo.',
      backLabel: 'Chẩn đoán',
      children: [
        GroupSection(
          header: 'Vòng đeo',
          children: [
            FieldRow(
              label: 'Địa chỉ vòng đeo',
              controller: _url,
              fieldKey: const Key('wearableUrl'),
              keyboardType: TextInputType.url,
              hint: learned.isEmpty ? 'http://baonga.local hoặc 192.168.x.x' : learned,
            ),
            FieldRow(
              label: 'Mật khẩu trang thiết bị (nếu có)',
              controller: _pass,
              fieldKey: const Key('wearablePassword'),
              obscure: true,
            ),
            ListRow(
              title: 'Dùng địa chỉ baonga.local',
              accent: true,
              onTap: () => setState(() => _url.text = 'http://baonga.local'),
            ),
          ],
        ),
        FilledButton(
          onPressed: () async {
            await c.saveWearableConnection(_url.text, _pass.text);
            if (context.mounted) showSnack(context, 'Đã lưu.');
          },
          child: const Text('Lưu kết nối'),
        ),
        GroupSection(
          header: 'Mã định danh',
          children: [
            FieldRow(label: 'Mã thiết bị', controller: _deviceId),
            FieldRow(label: 'Mã nhà', controller: _homeId),
          ],
        ),
        FilledButton(
          onPressed: () async {
            await c.saveIds(_deviceId.text.trim(), _homeId.text.trim());
            if (context.mounted) showSnack(context, 'Đã lưu.');
          },
          child: const Text('Lưu mã'),
        ),
      ],
    );
  }
}
