import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/cloud_settings.dart';
import '../../core/protocol/notify_validation.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Các mốc "Báo khi không cử động" (phút); 0 = tắt.
const List<int> kInactiveOptions = [0, 15, 30, 60, 120, 240];

/// Telegram, Email và ngưỡng không cử động; lưu một lần bằng nút "Lưu".
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, this.initial});

  /// Cài đặt đã tải sẵn từ tab Cài đặt (null thì tự tải).
  final AlertSettingsState? initial;

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final _chatIds = TextEditingController();
  final _emailTo = TextEditingController();

  bool _telegramOn = false;
  bool _gmailOn = false;
  bool _telegramAvail = true;
  bool _gmailAvail = true;
  int _inactiveMin = CloudSettings.defaultInactiveMin;
  bool _loading = false;
  bool _saving = false;
  String? _loadError;
  String? _formError;
  String? _info;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _apply(init);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _chatIds.dispose();
    _emailTo.dispose();
    super.dispose();
  }

  void _apply(AlertSettingsState st) {
    _telegramOn = st.settings.telegramOn;
    _gmailOn = st.settings.gmailOn;
    _chatIds.text = st.settings.chatIds;
    _emailTo.text = st.settings.emailTo;
    _inactiveMin = st.settings.inactiveMin;
    _telegramAvail = st.telegramAvailable;
    _gmailAvail = st.gmailAvailable;
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
      setState(() => _apply(st));
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final c = context.read<AppController>();
    final minutes = parseMinutes('$_inactiveMin');
    if (minutes == null) {
      setState(() {
        _formError = 'Số phút không cử động phải là số nguyên không âm.';
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

  static String _minLabel(int m) {
    if (m == 0) return 'Tắt';
    if (m % 60 == 0) return '${m ~/ 60} giờ';
    return '$m phút';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final t = context.tokens;
    final readOnly = !c.canEditSettings;
    final appliedError = c.cloudApplied['error'];
    final options = {...kInactiveOptions, _inactiveMin}.toList()..sort();

    return SubPage(
      title: 'Thông báo',
      subtitle: 'Chọn cách nhận tin khi có sự cố.',
      children: [
        if (readOnly) InlineNote('Bạn chỉ có quyền xem.', color: t.warnText, bg: t.warnTint),
        if (_loadError != null)
          GroupSection(children: [
            ListRow(
              title: 'Không tải được cài đặt',
              subtitle: _loadError,
              subtitleColor: t.warnText,
              minHeight: 64,
            ),
            ListRow(
              title: _loading ? 'Đang tải…' : 'Thử lại',
              accent: true,
              onTap: _loading ? null : _load,
            ),
          ]),
        GroupSection(
          header: 'Telegram',
          children: [
            SwitchRow(
              title: 'Gửi qua Telegram',
              value: _telegramOn,
              onChanged: readOnly ? null : (v) => setState(() => _telegramOn = v),
            ),
            FieldRow(
              label: 'ID cuộc trò chuyện (cách nhau bằng dấu phẩy)',
              controller: _chatIds,
              fieldKey: const Key('chatIds'),
              enabled: !readOnly,
              hint: 'Ví dụ: 123456789, 987654321',
            ),
          ],
        ),
        GroupSection(
          header: 'Email',
          children: [
            SwitchRow(
              title: 'Gửi qua email',
              value: _gmailOn,
              onChanged: readOnly ? null : (v) => setState(() => _gmailOn = v),
            ),
            FieldRow(
              label: 'Địa chỉ nhận (cách nhau bằng dấu phẩy)',
              controller: _emailTo,
              fieldKey: const Key('emailTo'),
              enabled: !readOnly,
              keyboardType: TextInputType.emailAddress,
              hint: 'Ví dụ: ten@gmail.com',
            ),
          ],
        ),
        KeyedSubtree(
          key: const Key('inactiveMin'),
          child: GroupSection(
            header: 'Báo khi không cử động',
            footer: 'Gửi tin khi người được theo dõi nằm yên quá lâu.',
            children: [
              for (final m in options)
                ListRow(
                  title: _minLabel(m),
                  trailing: m == _inactiveMin
                      ? Icon(Icons.check_rounded, color: t.primary)
                      : null,
                  onTap: readOnly ? null : () => setState(() => _inactiveMin = m),
                  showChevron: false,
                ),
            ],
          ),
        ),
        if (_formError != null)
          Text(_formError!, style: TextStyle(fontSize: 14, color: t.badText)),
        if (_info != null) Text(_info!, style: TextStyle(fontSize: 14, color: t.okText)),
        if (appliedError is String && appliedError.isNotEmpty)
          Text('Thiết bị báo lỗi: $appliedError',
              style: TextStyle(fontSize: 14, color: t.badText)),
        FilledButton(
          key: const Key('saveSettings'),
          onPressed: (readOnly || _saving) ? null : _save,
          child: Text(_saving ? 'Đang lưu…' : 'Lưu'),
        ),
      ],
    );
  }
}
