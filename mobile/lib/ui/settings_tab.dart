import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/presence.dart';
import '../state/app_controller.dart';
import 'diagnostics_page.dart';
import 'settings/camera_settings_page.dart';
import 'settings/notification_settings_page.dart';
import 'settings/person_name_page.dart';
import 'settings/wearable_settings_page.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Phiên bản hiển thị ở chân trang Cài đặt (khớp pubspec.yaml).
const String kAppVersion = '1.1.0';

/// Tab "Cài đặt": danh sách nhóm, mỗi dòng mở một trang con.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  AlertSettingsState? _alert;
  bool _loading = false;
  bool _loadFailed = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final c = context.read<AppController>();
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final st = await c.loadAlertSettings();
      if (mounted) setState(() => _alert = st);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
    if (mounted) _load();
  }

  Future<void> _test(AppController c) async {
    setState(() => _testing = true);
    final msg = await c.sendTest();
    if (!mounted) return;
    setState(() => _testing = false);
    showSnack(context, msg);
  }

  Future<void> _clear(AppController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa lịch sử sự cố?'),
        content: const Text('Toàn bộ lịch sử sự cố trên điện thoại sẽ bị xóa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: context.tokens.badText),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok == true) await c.clearLog();
  }

  String _telegramValue() {
    final s = _alert?.settings;
    if (s == null) return _loading ? '…' : '';
    if (!s.telegramOn) return 'Tắt';
    return '${_count(s.chatIds)} người nhận';
  }

  String _emailValue() {
    final s = _alert?.settings;
    if (s == null) return _loading ? '…' : '';
    if (!s.gmailOn) return 'Tắt';
    return '${_count(s.emailTo)} địa chỉ';
  }

  String _inactiveValue() {
    final s = _alert?.settings;
    if (s == null) return _loading ? '…' : '';
    return s.inactiveMin > 0 ? 'Sau ${s.inactiveMin} phút' : 'Tắt';
  }

  static int _count(String csv) => csv.split(',').where((e) => e.trim().isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final t = context.tokens;
    void openNotif() => _push(NotificationSettingsPage(initial: _alert));

    final String wearableValue;
    switch (c.wearablePresence) {
      case WearablePresence.online:
        wearableValue = 'Đang kết nối';
      case WearablePresence.offline:
        wearableValue = 'Mất kết nối';
      case WearablePresence.unknown:
        wearableValue = 'Chưa có dữ liệu';
    }
    final paired = c.settings.pairedCameras.isNotEmpty;
    final cameraValue = !paired
        ? 'Chưa ghép'
        : ((c.cameraConnected && c.cameraAuthenticated) ? 'Đang theo dõi' : 'Đã ghép');

    final String accountTitle;
    final String accountSub;
    if (c.signedIn) {
      accountTitle = c.email ?? '';
      accountSub = c.role == 'owner'
          ? 'Chủ sở hữu · được sửa cài đặt'
          : (c.role == 'viewer' ? 'Người xem · chỉ xem' : 'Đã đăng nhập');
    } else {
      accountTitle = 'Chế độ nội mạng · không đăng nhập';
      accountSub = '';
    }

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
        children: [
          const LargeTitle('Cài đặt'),
          const SizedBox(height: 22),
          GroupSection(header: 'Gia đình', children: [
            ListRow(
              title: 'Người được theo dõi',
              value: c.personName,
              onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const PersonNamePage())),
            ),
          ]),
          const SizedBox(height: 22),
          GroupSection(header: 'Thông báo', children: [
            if (_loadFailed)
              ListRow(
                title: 'Không tải được cài đặt thông báo',
                subtitle: 'Chạm để thử lại',
                subtitleColor: t.warnText,
                onTap: _load,
                showChevron: false,
              ),
            ListRow(title: 'Telegram', value: _telegramValue(), onTap: openNotif),
            ListRow(title: 'Email', value: _emailValue(), onTap: openNotif),
            ListRow(title: 'Báo khi không cử động', value: _inactiveValue(), onTap: openNotif),
            ListRow(
              title: 'Gửi tin nhắn thử',
              accent: true,
              trailing: _testing
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: _testing ? null : () => _test(c),
            ),
          ]),
          const SizedBox(height: 22),
          GroupSection(header: 'Thiết bị', children: [
            ListRow(
              title: 'Vòng đeo',
              value: wearableValue,
              onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const WearableSettingsPage())),
            ),
            ListRow(
              title: 'Camera',
              value: cameraValue,
              onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const CameraSettingsPage())),
            ),
            ListRow(
              title: 'Thêm camera',
              accent: true,
              onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const CameraSettingsPage())),
            ),
          ]),
          const SizedBox(height: 22),
          GroupSection(header: 'Ứng dụng', children: [
            if (c.isAndroid)
              SwitchRow(
                title: 'Nhận cảnh báo khi đóng app',
                value: c.settings.useBackgroundService,
                onChanged: c.setUseBackgroundService,
              ),
            if (c.isIOS)
              SwitchRow(
                title: 'Giữ app hoạt động nền',
                value: c.settings.iosKeepAlive,
                onChanged: c.setIosKeepAlive,
              ),
            if (c.isAndroid)
              ListRow(
                title: 'Tối ưu pin',
                onTap: () async {
                  final ok = await c.requestBatteryOptimization();
                  if (context.mounted) {
                    showSnack(context, ok ? 'Đã bỏ tối ưu pin cho ứng dụng.' : 'Chưa bỏ tối ưu pin.');
                  }
                },
              ),
            ListRow(
              title: 'Quyền ứng dụng',
              onTap: () async {
                final r = await c.requestAllPermissions();
                if (context.mounted) showSnack(context, r);
              },
            ),
            ListRow(
              title: 'Chẩn đoán',
              onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const DiagnosticsPage())),
            ),
            ListRow(
                title: 'Xóa lịch sử sự cố', destructive: true, onTap: () => _clear(c)),
          ]),
          const SizedBox(height: 22),
          GroupSection(header: 'Tài khoản', children: [
            ListRow(
              title: accountTitle,
              subtitle: accountSub.isEmpty ? null : accountSub,
              minHeight: 60,
            ),
            ListRow(
              title: c.signedIn ? 'Đăng xuất' : 'Đăng nhập',
              destructive: c.signedIn,
              accent: !c.signedIn,
              onTap: c.signOut,
            ),
          ]),
          const SizedBox(height: 16),
          Center(
            child: Text('Báo Ngã IoT $kAppVersion',
                style: TextStyle(fontSize: 13, color: t.textSub)),
          ),
        ],
      ),
    );
  }
}
