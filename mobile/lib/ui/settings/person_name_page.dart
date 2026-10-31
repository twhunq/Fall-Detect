import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Đặt tên người được theo dõi (hiện trên màn hình chính và trong cảnh báo).
class PersonNamePage extends StatefulWidget {
  const PersonNamePage({super.key});

  @override
  State<PersonNamePage> createState() => _PersonNamePageState();
}

class _PersonNamePageState extends State<PersonNamePage> {
  late final TextEditingController _name;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: context.read<AppController>().personName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = context.read<AppController>();
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final err = await c.savePersonName(_name.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      showSnack(context, err);
      return;
    }
    showSnack(context, 'Đã lưu.');
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final t = context.tokens;
    final canEdit = c.canEditPersonName;
    return SubPage(
      title: 'Người được theo dõi',
      subtitle: 'Tên này hiện trên màn hình chính và trong cảnh báo.',
      children: [
        GroupSection(
          footer: canEdit ? null : 'Bạn chỉ có quyền xem.',
          children: [
            FieldRow(
              label: 'Tên gọi',
              controller: _name,
              fieldKey: const Key('personName'),
              enabled: canEdit,
              hint: 'Ví dụ: Mẹ',
            ),
          ],
        ),
        if (canEdit)
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Đang lưu…' : 'Lưu'),
          )
        else
          Text('Chỉ chủ sở hữu mới đổi được tên.',
              style: TextStyle(fontSize: 13, color: t.textSub)),
      ],
    );
  }
}
