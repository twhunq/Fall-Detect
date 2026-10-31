import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/cloud_settings.dart';
import '../core/protocol/notify_validation.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'widgets/common.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _chatIds = TextEditingController();
  final _emailTo = TextEditingController();
  final _inactive = TextEditingController(text: '${CloudSettings.defaultInactiveMin}');
  final _deviceId = TextEditingController();
  final _homeId = TextEditingController();
  final _sosName = TextEditingController();
  final _sosPhone = TextEditingController();

  bool _telegramOn = false;
  bool _gmailOn = false;
  bool _telegramAvail = true;
  bool _gmailAvail = true;
  bool _loading = false;
  bool _saving = false;
  bool _testing = false;
  String? _loadError;
  String? _formError;
  String? _info;
  String? _testResult;
  String? _permResult;

  @override
  void initState() {
    super.initState();
    final c = context.read<AppController>();
    _deviceId.text = c.settings.deviceId;
    _homeId.text = c.settings.homeId;
    _sosName.text = c.settings.sosName;
    _sosPhone.text = c.settings.sosPhone;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final t in [_chatIds, _emailTo, _inactive, _deviceId, _homeId, _sosName, _sosPhone]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final c = context.read<AppController>();
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final st = await c.loadAlertSettings();
      if (!mounted) return;
      setState(() {
        _telegramOn = st.settings.telegramOn;
        _gmailOn = st.settings.gmailOn;
        _chatIds.text = st.settings.chatIds;
        _emailTo.text = st.settings.emailTo;
        _inactive.text = '${st.settings.inactiveMin}';
        _telegramAvail = st.telegramAvailable;
        _gmailAvail = st.gmailAvailable;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final c = context.read<AppController>();
    final minutes = parseMinutes(_inactive.text.trim());
    if (minutes == null) {
      setState(() {
        _formError = 'Số phút bất động phải là số nguyên không âm.';
        _info = null;
      });
      return;
    }
    final v = buildSettings(
      telegramOn: _telegramOn,
      gmailOn: _gmailOn,
      chatIds: _chatIds.text,
      emailTo: _emailTo.text,
      inactiveMin: minutes,
      telegramAvailable: _telegramAvail,
      gmailAvailable: _gmailAvail,
    );
    if (!v.ok) {
      setState(() {
        _formError = v.error;
        _info = null;
      });
      return;
    }
    setState(() {
      _formError = null;
      _saving = true;
    });
    final err = await c.saveAlertSettings(v.settings!);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (err == null) {
        _info = 'Đã lưu cài đặt.';
        _chatIds.text = v.settings!.chatIds;
        _emailTo.text = v.settings!.emailTo;
      } else {
        _formError = err;
        _info = null;
      }
    });
  }

  Future<void> _test() async {
    final c = context.read<AppController>();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final msg = await c.sendTest();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final colors = context.statusColors;
    final readOnly = !c.canEditSettings;
    final applied = c.cloudApplied;
    final appliedError = applied['error'];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (readOnly) ...[
          StatusBanner(
              text: 'Bạn chỉ có quyền xem', icon: Icons.visibility, color: colors.warn),
          const SizedBox(height: 10),
        ],
        SectionCard(
          title: 'Cài đặt cảnh báo',
          trailing: IconButton(
            tooltip: 'Tải lại',
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.signedIn ? 'Nguồn: Cloud (đã đăng nhập)' : 'Nguồn: mạng nội bộ (LAN)',
                style: TextStyle(color: colors.muted),
              ),
              if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_loadError!, style: TextStyle(color: colors.warn)),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gửi qua Telegram'),
                value: _telegramOn,
                onChanged: readOnly ? null : (v) => setState(() => _telegramOn = v),
              ),
              TextField(
                key: const Key('chatIds'),
                controller: _chatIds,
                enabled: !readOnly,
                decoration: const InputDecoration(
                    labelText: 'Chat ID (phân tách bằng dấu phẩy)',
                    border: OutlineInputBorder()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gửi qua Gmail'),
                value: _gmailOn,
                onChanged: readOnly ? null : (v) => setState(() => _gmailOn = v),
              ),
              TextField(
                key: const Key('emailTo'),
                controller: _emailTo,
                enabled: !readOnly,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Email nhận (phân tách bằng dấu phẩy)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('inactiveMin'),
                controller: _inactive,
                enabled: !readOnly,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Cảnh báo bất động sau (phút, 0 = tắt)',
                    border: OutlineInputBorder()),
              ),
              if (_formError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_formError!, style: TextStyle(color: colors.bad)),
                ),
              if (_info != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_info!, style: TextStyle(color: colors.ok)),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const Key('saveSettings'),
                    onPressed: (readOnly || _saving) ? null : _save,
                    child: Text(_saving ? 'Đang lưu…' : 'Lưu cài đặt'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: const Icon(Icons.send),
                    label: Text(_testing ? 'Đang gửi…' : 'Gửi tin thử'),
                  ),
                ],
              ),
              if (_testResult != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Kết quả: $_testResult'),
                ),
              if (appliedError is String && appliedError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Lỗi từ thiết bị: $appliedError',
                      style: TextStyle(color: colors.bad)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'SOS',
          child: Column(
            children: [
              TextField(
                controller: _sosName,
                decoration: const InputDecoration(
                    labelText: 'Tên người thân', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('sosPhone'),
                controller: _sosPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Số điện thoại SOS (trống = 115)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: () async {
                    await c.saveSos(_sosName.text, _sosPhone.text);
                    if (context.mounted) showSnack(context, 'Đã lưu SOS.');
                  },
                  child: const Text('Lưu SOS'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Thiết bị',
          child: Column(
            children: [
              TextField(
                controller: _deviceId,
                decoration: const InputDecoration(
                    labelText: 'Mã thiết bị (deviceId)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _homeId,
                decoration: const InputDecoration(
                    labelText: 'Mã nhà (homeId)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: () async {
                    await c.saveIds(_deviceId.text.trim(), _homeId.text.trim());
                    if (context.mounted) showSnack(context, 'Đã lưu.');
                  },
                  child: const Text('Lưu'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Ứng dụng',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c.isAndroid) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Giám sát nền (foreground service)'),
                  subtitle: const Text('Bật để vẫn nhận cảnh báo khi đóng ứng dụng.'),
                  value: c.settings.useBackgroundService,
                  onChanged: c.setUseBackgroundService,
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await c.requestBatteryOptimization();
                    if (context.mounted) {
                      showSnack(context, ok ? 'Đã bỏ tối ưu pin.' : 'Chưa bỏ tối ưu pin.');
                    }
                  },
                  icon: const Icon(Icons.battery_saver),
                  label: const Text('Bỏ tối ưu pin'),
                ),
              ],
              if (c.isIOS)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Giữ ứng dụng hoạt động nền'),
                  subtitle: const Text('Phát âm thanh im lặng để iOS không tạm dừng ứng dụng.'),
                  value: c.settings.iosKeepAlive,
                  onChanged: c.setIosKeepAlive,
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await c.requestAllPermissions();
                  if (mounted) setState(() => _permResult = r);
                },
                icon: const Icon(Icons.security),
                label: const Text('Cấp quyền'),
              ),
              if (_permResult != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_permResult!, style: TextStyle(color: colors.muted)),
                ),
              const Divider(height: 24),
              if (c.signedIn) Text('Đã đăng nhập: ${c.email ?? ''} (${c.role ?? 'không rõ quyền'})'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: c.signOut,
                icon: Icon(c.signedIn ? Icons.logout : Icons.login),
                label: Text(c.signedIn ? 'Đăng xuất' : 'Đăng nhập tài khoản'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
