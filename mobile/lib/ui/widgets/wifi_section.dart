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
      setState(() => _error = 'Chưa biết địa chỉ vòng đeo. Nhập địa chỉ ở Cài đặt › Chẩn đoán › Kết nối thủ công.');
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
    final t = context.tokens;
    final w = _wifi;
    final connected = (w?['connected'] as String?) ?? '';
    final networks = (w?['networks'] as List? ?? const []).whereType<Map>().toList();
    final attempt =
        w?['attempt'] is Map ? Map<String, dynamic>.from(w!['attempt'] as Map) : null;
    final spinner = const SizedBox(
        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupSection(
          header: 'Wi-Fi 2.4 GHz của vòng đeo',
          children: [
            if (w != null) ...[
              KeyValueRow('Đang kết nối', connected.isEmpty ? 'Chưa kết nối' : connected,
                  dot: connected.isEmpty ? t.warn : t.ok),
              if (connected.isNotEmpty)
                KeyValueRow('Địa chỉ IP · sóng', '${w['ip']} · ${w['rssi']} dBm'),
              if (w['ap'] == true)
                KeyValueRow('Mạng cài đặt', '${w['apName'] ?? ''} (${w['apIp'] ?? ''})'),
              if (attempt != null && attempt['state'] != 'none')
                KeyValueRow('Lần thử gần nhất',
                    '${attempt['ssid']}: ${_attemptText('${attempt['state']}')}'),
            ],
            ListRow(
              title: w == null ? 'Đọc cài đặt Wi-Fi từ vòng đeo' : 'Tải lại',
              accent: true,
              trailing: _loading ? spinner : null,
              onTap: _loading ? null : _refresh,
            ),
          ],
        ),
        if (w != null) ...[
          const SizedBox(height: 22),
          GroupSection(
            header: 'Mạng đã lưu',
            children: [
              if (networks.isEmpty) const ListRow(title: 'Chưa lưu mạng nào'),
              for (final n in networks)
                ListRow(
                  leading: Icon(n['open'] == true ? Icons.wifi_rounded : Icons.wifi_password_rounded,
                      color: t.textStrong),
                  title: '${n['ssid']}',
                  onTap: () => setState(() => _ssid.text = '${n['ssid']}'),
                  trailing: IconButton(
                    tooltip: 'Quên mạng',
                    icon: Icon(Icons.delete_outline_rounded, color: t.badText),
                    onPressed: _busy ? null : () => _forget('${n['ssid']}'),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        GroupSection(
          header: 'Mạng quanh vòng đeo',
          children: [
            for (final n in _scan)
              ListRow(
                leading: Icon(n['open'] == true ? Icons.wifi_rounded : Icons.wifi_password_rounded,
                    color: t.textStrong),
                title: '${n['ssid']}',
                value: '${n['rssi']} dBm',
                showChevron: false,
                onTap: () => setState(() => _ssid.text = '${n['ssid']}'),
              ),
            ListRow(
              title: _scanning ? 'Đang quét…' : 'Quét mạng',
              accent: true,
              trailing: _scanning ? spinner : null,
              onTap: _scanning ? null : _startScan,
            ),
          ],
        ),
        const SizedBox(height: 22),
        GroupSection(
          header: 'Kết nối mạng mới',
          footer: 'Mật khẩu dài 8-63 ký tự; để trống nếu là mạng mở hoặc đã lưu.',
          children: [
            FieldRow(
              label: 'Tên Wi-Fi',
              controller: _ssid,
              fieldKey: const Key('wifiSsid'),
            ),
            FieldRow(
              label: 'Mật khẩu',
              controller: _pass,
              fieldKey: const Key('wifiPass'),
              obscure: true,
            ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: Text(_busy ? 'Đang kết nối…' : 'Kết nối mạng này'),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(_message!, style: TextStyle(fontSize: 14, color: t.okText)),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(_error!, style: TextStyle(fontSize: 14, color: t.badText)),
          ),
      ],
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
