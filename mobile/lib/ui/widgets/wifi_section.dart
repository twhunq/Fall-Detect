import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/wearable_lan_service.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import 'common.dart';

/// Quản lý Wi-Fi 2.4 GHz của vòng đeo qua API cục bộ (/api/wifi).
class WifiSection extends StatefulWidget {
  const WifiSection({super.key});

  @override
  State<WifiSection> createState() => _WifiSectionState();
}

class _WifiSectionState extends State<WifiSection> {
  final _ssid = TextEditingController();
  final _pass = TextEditingController();
  Map<String, dynamic>? _wifi;
  List<Map<String, dynamic>> _scan = const [];
  String? _error;
  String? _message;
  bool _loading = false;
  bool _scanning = false;
  bool _busy = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<T?> _withLan<T>(Future<T> Function(WearableLanService lan) f) async {
    final lan = context.read<AppController>().newLanService();
    if (lan == null) {
      setState(() => _error = 'Chưa biết địa chỉ vòng đeo. Nhập địa chỉ ở phần "Kết nối".');
      return null;
    }
    try {
      return await f(lan);
    } on LanException catch (e) {
      if (!_disposed) setState(() => _error = e.message);
      return null;
    } finally {
      lan.close();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final w = await _withLan((l) => l.getWifi());
    if (_disposed) return;
    setState(() {
      _loading = false;
      if (w != null) _wifi = w;
    });
  }

  Future<void> _startScan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
      _scan = const [];
    });
    final lan = context.read<AppController>().newLanService();
    if (lan == null) {
      setState(() {
        _scanning = false;
        _error = 'Chưa biết địa chỉ vòng đeo.';
      });
      return;
    }
    try {
      var first = true;
      for (var i = 0; i < 20 && !_disposed; i++) {
        final r = await lan.scanWifi(fresh: first);
        first = false;
        if (r['scanning'] != true) {
          final list = (r['list'] as List? ?? const [])
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
          if (!_disposed) {
            setState(() {
              _scan = list;
              if (r['error'] == true) _error = 'Vòng đeo không quét được Wi-Fi.';
            });
          }
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } on LanException catch (e) {
      if (!_disposed) setState(() => _error = e.message);
    } finally {
      lan.close();
      if (!_disposed) setState(() => _scanning = false);
    }
  }

  Future<void> _connect() async {
    final ssid = _ssid.text;
    final pass = _pass.text;
    final bytes = ssid.codeUnits.length;
    if (bytes < 1 || bytes > 32) {
      setState(() => _error = 'Tên Wi-Fi phải dài 1-32 byte.');
      return;
    }
    if (pass.isNotEmpty && (pass.length < 8 || pass.length > 63)) {
      setState(() => _error =
          'Mật khẩu Wi-Fi phải dài 8-63 ký tự (hoặc để trống nếu mạng mở/đã lưu).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    final r = await _withLan((l) => l.connectWifi(ssid, pass));
    if (_disposed) return;
    setState(() {
      _busy = false;
      if (r != null) {
        if (r.ok) {
          _message = r.message;
        } else {
          _error = r.message;
        }
      }
    });
    if (r != null && r.ok) {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!_disposed) await _refresh();
    }
  }

  Future<void> _forget(String ssid) async {
    setState(() => _busy = true);
    final r = await _withLan((l) => l.forgetWifi(ssid));
    if (_disposed) return;
    setState(() {
      _busy = false;
      if (r != null) {
        if (r.ok) {
          _message = r.message;
        } else {
          _error = r.message;
        }
      }
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final w = _wifi;
    final connected = (w?['connected'] as String?) ?? '';
    final networks = (w?['networks'] as List? ?? const []).whereType<Map>().toList();
    final attempt =
        w?['attempt'] is Map ? Map<String, dynamic>.from(w!['attempt'] as Map) : null;
    return SectionCard(
      title: 'Wi-Fi 2.4 GHz của vòng đeo',
      trailing: IconButton(
        tooltip: 'Tải lại',
        onPressed: _loading ? null : _refresh,
        icon: _loading
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (w == null)
            Text('Bấm tải lại để đọc danh sách mạng từ vòng đeo.',
                style: TextStyle(color: colors.muted))
          else ...[
            InfoRow('Đang kết nối', connected.isEmpty ? 'Chưa kết nối' : connected,
                color: connected.isEmpty ? colors.warn : colors.ok),
            if (connected.isNotEmpty) InfoRow('IP / RSSI', '${w['ip']} / ${w['rssi']} dBm'),
            if (w['ap'] == true) InfoRow('Hotspot', '${w['apName'] ?? ''} (${w['apIp'] ?? ''})'),
            if (attempt != null && attempt['state'] != 'none')
              InfoRow('Lần thử', '${attempt['ssid']}: ${_attemptText('${attempt['state']}')}'),
            const SizedBox(height: 6),
            Text('Mạng đã lưu', style: Theme.of(context).textTheme.labelLarge),
            if (networks.isEmpty)
              Text('Chưa lưu mạng nào.', style: TextStyle(color: colors.muted)),
            for (final n in networks)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(n['open'] == true ? Icons.wifi : Icons.wifi_password),
                title: Text('${n['ssid']}'),
                onTap: () => setState(() => _ssid.text = '${n['ssid']}'),
                trailing: IconButton(
                  tooltip: 'Quên mạng',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _forget('${n['ssid']}'),
                ),
              ),
          ],
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                  child: Text('Mạng quanh vòng đeo',
                      style: Theme.of(context).textTheme.labelLarge)),
              TextButton.icon(
                onPressed: _scanning ? null : _startScan,
                icon: _scanning
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_find),
                label: Text(_scanning ? 'Đang quét…' : 'Quét'),
              ),
            ],
          ),
          for (final n in _scan)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(n['open'] == true ? Icons.wifi : Icons.wifi_password),
              title: Text('${n['ssid']}'),
              subtitle: Text('${n['rssi']} dBm'),
              onTap: () => setState(() => _ssid.text = '${n['ssid']}'),
            ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('wifiSsid'),
            controller: _ssid,
            decoration: const InputDecoration(
                labelText: 'Tên Wi-Fi (SSID, 1-32 byte)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('wifiPass'),
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Mật khẩu (8-63 ký tự; trống = mạng mở/đã lưu)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _connect,
            icon: const Icon(Icons.link),
            label: const Text('Kết nối mạng này'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_message!, style: TextStyle(color: colors.ok)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: colors.bad)),
            ),
        ],
      ),
    );
  }

  static String _attemptText(String s) {
    switch (s) {
      case 'connecting':
        return 'đang kết nối';
      case 'ok':
        return 'thành công';
      case 'fail':
        return 'thất bại';
      default:
        return s;
    }
  }
}
