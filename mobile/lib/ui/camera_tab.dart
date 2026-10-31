import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/protocol/ble_protocol.dart';
import '../services/camera_ble_service.dart';
import '../state/app_controller.dart';
import 'qr_scan_page.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/mjpeg_view.dart';

class CameraTab extends StatelessWidget {
  const CameraTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _ScanCard(c: c),
        const SizedBox(height: 12),
        _StatusCard(c: c),
        if (c.cameraInfo?.streamUri != null) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Xem trực tiếp',
            child: MjpegView(uri: c.cameraInfo!.streamUri!),
          ),
        ],
        const SizedBox(height: 12),
        const _ConfigCard(),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.c});

  final AppController c;

  Future<void> _scanQr(BuildContext context) async {
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

  Future<void> _manual(BuildContext context) async {
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
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Ghép')),
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
    final colors = context.statusColors;
    return SectionCard(
      title: 'Tìm và ghép camera (BLE)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: c.scanning ? c.stopScan : c.startScan,
                icon: Icon(c.scanning ? Icons.stop : Icons.bluetooth_searching),
                label: Text(c.scanning ? 'Dừng quét' : 'Quét camera'),
              ),
              OutlinedButton.icon(
                onPressed: () => _scanQr(context),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Quét QR ghép nối'),
              ),
              TextButton(
                onPressed: () => _manual(context),
                child: const Text('Nhập mã thủ công'),
              ),
            ],
          ),
          if (c.scanError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(c.scanError!, style: TextStyle(color: colors.bad)),
            ),
          if (c.scanning && c.scanResults.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(),
            ),
          for (final r in c.scanResults) _ResultTile(c: c, r: r),
          if (c.settings.pairedCameras.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Camera đã ghép', style: Theme.of(context).textTheme.labelLarge),
            for (final id in c.settings.pairedCameras.keys)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.verified_outlined),
                title: Text(id),
                trailing: IconButton(
                  tooltip: 'Bỏ ghép',
                  icon: const Icon(Icons.link_off),
                  onPressed: () => c.unpairCamera(id),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.c, required this.r});

  final AppController c;
  final CameraScanResult r;

  @override
  Widget build(BuildContext context) {
    final paired = c.isPaired(r.deviceId);
    final colors = context.statusColors;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.videocam),
      title: Text(r.deviceId.isEmpty ? (r.name.isEmpty ? r.remoteId : r.name) : r.deviceId),
      subtitle: Text('RSSI ${r.rssi} dBm${paired ? ' · Đã ghép' : ''}',
          style: TextStyle(color: paired ? colors.ok : colors.muted)),
      trailing: FilledButton.tonal(
        onPressed: () async {
          final err = await c.connectCamera(r);
          if (err != null && context.mounted) showSnack(context, err);
        },
        child: const Text('Kết nối'),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.c});

  final AppController c;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final now = DateTime.now();
    final info = c.cameraInfo;
    return SectionCard(
      title: 'Trạng thái camera',
      trailing: c.cameraConnected
          ? TextButton(onPressed: c.disconnectCamera, child: const Text('Ngắt'))
          : null,
      child: Column(
        children: [
          InfoRow('Kết nối BLE', c.cameraConnected ? 'Đã kết nối' : 'Chưa kết nối',
              color: c.cameraConnected ? colors.ok : colors.muted),
          InfoRow('Xác thực', c.cameraAuthenticated ? 'OK' : 'Chưa xác thực',
              color: c.cameraAuthenticated ? colors.ok : colors.warn),
          InfoRow('ALIVE gần nhất', fmtAge(c.lastAlive, now)),
          InfoRow(
              'Wi-Fi camera',
              c.cameraWifi == null ? 'Chưa rõ' : (c.cameraWifi! ? 'Đã kết nối' : 'Chưa kết nối'),
              color: c.cameraWifi == true ? colors.ok : null),
          InfoRow('Luồng hình', info?.streamUri?.toString() ?? 'Chưa biết'),
          InfoRow(
              'Cảnh báo cuối',
              c.lastCameraAlertAt == null
                  ? 'Chưa có'
                  : '${fmtClock(c.lastCameraAlertAt!)} (${c.lastCameraAlertPercent?.toStringAsFixed(0)}%)'),
          if (c.cameraMessage != null) InfoRow('Ghi chú', c.cameraMessage!),
        ],
      ),
    );
  }
}

class _ConfigCard extends StatefulWidget {
  const _ConfigCard();

  @override
  State<_ConfigCard> createState() => _ConfigCardState();
}

class _ConfigCardState extends State<_ConfigCard> {
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
      _result = _ok ? 'OK — đã ghi cấu hình.' : r;
    });
  }

  Widget _field(String label, TextEditingController ctl, {bool secret = false, Key? key}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: key,
        controller: ctl,
        obscureText: secret,
        autocorrect: false,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final c = context.watch<AppController>();
    return SectionCard(
      title: 'Cấu hình camera (qua BLE)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Để trống một ô = giữ nguyên giá trị hiện có trên camera.',
              style: TextStyle(color: colors.muted)),
          const SizedBox(height: 10),
          _field('Tên Wi-Fi (SSID)', _ssid),
          _field('Mật khẩu Wi-Fi', _pass, secret: true),
          _field('Bot token Telegram', _token, secret: true),
          _field('Chat ID', _chat),
          _field('Mã nhà', _home),
          _field('Địa chỉ relay (URL)', _relay),
          FilledButton.icon(
            onPressed: (_busy || !c.cameraAuthenticated) ? null : _send,
            icon: const Icon(Icons.upload),
            label: const Text('Ghi cấu hình'),
          ),
          if (!c.cameraAuthenticated)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Cần kết nối và xác thực camera trước.',
                  style: TextStyle(color: colors.muted)),
            ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_result!, style: TextStyle(color: _ok ? colors.ok : colors.bad)),
            ),
          const SizedBox(height: 8),
          Text('Lưu ý: cần khởi động lại cầu nối (rút/cắm nguồn) để áp dụng Wi-Fi mới.',
              style: TextStyle(color: colors.warn)),
        ],
      ),
    );
  }
}
