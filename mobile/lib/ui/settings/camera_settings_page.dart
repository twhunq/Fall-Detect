import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/ble_protocol.dart';
import '../../state/app_controller.dart';
import '../qr_scan_page.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Ghép, kết nối và cấu hình camera AI (qua Bluetooth).
class CameraSettingsPage extends StatelessWidget {
  const CameraSettingsPage({super.key});

  Future<void> _scanQr(BuildContext context, AppController c) async {
    final cam = await c.permissions.requestCamera();
    if (!context.mounted) return;
    if (!cam) {
      showSnack(context, 'Chưa được cấp quyền camera. Có thể nhập mã thủ công.');
      return;
    }
    final text = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));
    if (text == null || !context.mounted) return;
    final err = await c.pairFromUri(text);
    if (context.mounted) showSnack(context, err ?? 'Đã ghép nối camera.');
  }

  Future<void> _manual(BuildContext context, AppController c) async {
    final ctl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nhập mã ghép nối'),
        content: TextField(
          key: const Key('pairUriField'),
          controller: ctl,
          decoration: const InputDecoration(hintText: 'cbn://pair?id=CBC-XXXXXX&key=...'),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Ghép')),
        ],
      ),
    );
    ctl.dispose();
    if (text == null || !context.mounted) return;
    final err = await c.pairFromUri(text);
    if (context.mounted) showSnack(context, err ?? 'Đã ghép nối camera.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final t = context.tokens;
    final now = DateTime.now();
    final paired = c.settings.pairedCameras.keys.toList();
    final info = c.cameraInfo;
    return SubPage(
      title: 'Camera',
      subtitle: 'Ghép camera AI để theo dõi thêm bằng hình ảnh.',
      children: [
        GroupSection(
          header: 'Camera đã ghép',
          children: [
            if (paired.isEmpty) const ListRow(title: 'Chưa ghép camera nào'),
            for (final id in paired)
              ListRow(
                leading: const IconTile(icon: Icons.videocam_rounded),
                title: id,
                subtitle: (c.connectedCameraId == id && c.cameraConnected)
                    ? (c.cameraAuthenticated ? 'Đang theo dõi' : 'Đã kết nối · chưa xác thực')
                    : 'Đã ghép',
                dot: (c.connectedCameraId == id && c.cameraConnected && c.cameraAuthenticated)
                    ? t.ok
                    : t.chevron,
                trailing: IconButton(
                  tooltip: 'Bỏ ghép',
                  icon: Icon(Icons.link_off_rounded, color: t.badText),
                  onPressed: () => c.unpairCamera(id),
                ),
              ),
            if (c.cameraConnected)
              ListRow(title: 'Ngắt kết nối', destructive: true, onTap: c.disconnectCamera),
          ],
        ),
        if (c.cameraConnected)
          GroupSection(
            header: 'Tình trạng',
            children: [
              KeyValueRow('Xác thực', c.cameraAuthenticated ? 'Đã xác thực' : 'Chưa xác thực',
                  dot: c.cameraAuthenticated ? t.ok : t.warn),
              KeyValueRow('Tín hiệu gần nhất', fmtAge(c.lastAlive, now)),
              KeyValueRow(
                  'Wi-Fi của camera',
                  c.cameraWifi == null
                      ? 'Chưa rõ'
                      : (c.cameraWifi! ? 'Đã kết nối' : 'Chưa kết nối')),
              if (info?.streamUri != null)
                KeyValueRow('Luồng hình', info!.streamUri.toString(), small: true),
            ],
          ),
        GroupSection(
          header: 'Thêm camera',
          children: [
            ListRow(
              leading: IconTile(
                  icon: Icons.qr_code_scanner_rounded, bg: t.primaryTint, fg: t.primary),
              title: 'Quét mã QR ghép nối',
              accent: true,
              minHeight: 64,
              onTap: () => _scanQr(context, c),
            ),
            ListRow(
              leading: IconTile(icon: Icons.keyboard_rounded, bg: t.primaryTint, fg: t.primary),
              title: 'Nhập mã thủ công',
              accent: true,
              minHeight: 64,
              onTap: () => _manual(context, c),
            ),
            ListRow(
              leading: IconTile(
                  icon: c.scanning
                      ? Icons.stop_rounded
                      : Icons.bluetooth_searching_rounded,
                  bg: t.primaryTint,
                  fg: t.primary),
              title: c.scanning ? 'Dừng tìm' : 'Tìm camera gần đây',
              accent: true,
              minHeight: 64,
              onTap: c.scanning ? c.stopScan : c.startScan,
            ),
          ],
        ),
        if (c.scanError != null)
          Text(c.scanError!, style: TextStyle(fontSize: 14, color: t.badText)),
        if (c.scanning && c.scanResults.isEmpty) const LinearProgressIndicator(),
        if (c.scanResults.isNotEmpty)
          GroupSection(
            header: 'Camera tìm thấy',
            children: [
              for (final r in c.scanResults)
                ListRow(
                  leading: const IconTile(icon: Icons.videocam_rounded),
                  title: r.deviceId.isEmpty
                      ? (r.name.isEmpty ? r.remoteId : r.name)
                      : r.deviceId,
                  subtitle: 'Sóng ${r.rssi} dBm${c.isPaired(r.deviceId) ? ' · Đã ghép' : ''}',
                  subtitleColor: c.isPaired(r.deviceId) ? t.okText : null,
                  trailing: TextButton(
                    onPressed: () async {
                      final err = await c.connectCamera(r);
                      if (err != null && context.mounted) showSnack(context, err);
                    },
                    child: const Text('Kết nối'),
                  ),
                ),
            ],
          ),
        if (c.cameraMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(c.cameraMessage!,
                style: TextStyle(fontSize: 14, color: t.textSub)),
          ),
        const _ConfigSection(),
      ],
    );
  }
}

class _ConfigSection extends StatefulWidget {
  const _ConfigSection();

  @override
  State<_ConfigSection> createState() => _ConfigSectionState();
}

class _ConfigSectionState extends State<_ConfigSection> {
  final _ssid = TextEditingController();
  final _pass = TextEditingController();
  final _token = TextEditingController();
  final _chat = TextEditingController();
  final _home = TextEditingController();
  final _relay = TextEditingController();
  String? _result;
  bool _ok = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final t in [_ssid, _pass, _token, _chat, _home, _relay]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final c = context.read<AppController>();
    setState(() {
      _busy = true;
      _result = null;
    });
    final r = await c.writeCameraConfig(CameraConfig(
      ssid: _ssid.text,
      password: _pass.text,
      token: _token.text,
      chatId: _chat.text,
      homeId: _home.text,
      relayUrl: _relay.text,
    ));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = r.trim() == 'OK';
      _result = _ok ? 'Đã ghi cấu hình vào camera.' : r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = context.watch<AppController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupSection(
          header: 'Cấu hình camera',
          footer: 'Để trống một ô để giữ nguyên giá trị hiện có trên camera. '
              'Sau khi ghi, rút và cắm lại nguồn cầu nối để áp dụng Wi-Fi mới.',
          children: [
            FieldRow(label: 'Tên Wi-Fi', controller: _ssid),
            FieldRow(label: 'Mật khẩu Wi-Fi', controller: _pass, obscure: true),
            FieldRow(label: 'Mã bot Telegram', controller: _token, obscure: true),
            FieldRow(label: 'ID cuộc trò chuyện Telegram', controller: _chat),
            FieldRow(label: 'Mã nhà', controller: _home),
            FieldRow(label: 'Địa chỉ máy chủ chuyển tiếp (URL)', controller: _relay),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: (_busy || !c.cameraAuthenticated) ? null : _send,
          child: Text(_busy ? 'Đang ghi…' : 'Ghi cấu hình'),
        ),
        if (!c.cameraAuthenticated)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text('Cần kết nối và xác thực camera trước.',
                style: TextStyle(fontSize: 13, color: t.textSub)),
          ),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(_result!,
                style: TextStyle(fontSize: 14, color: _ok ? t.okText : t.badText)),
          ),
      ],
    );
  }
}
