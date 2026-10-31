import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fusion/alert_models.dart';
import '../state/app_controller.dart';
import 'incident_detail_page.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/incident_ui.dart';

enum _Filter { all, fall, still }

/// Tab "Lịch sử": sự cố nhóm theo ngày, có bộ lọc.
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  _Filter _filter = _Filter.all;

  bool _match(AlertIncident i) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.fall:
        return i.kind == AlertKind.fall;
      case _Filter.still:
        return i.kind == AlertKind.inactive || i.kind == AlertKind.resumed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final t = context.tokens;
    final now = DateTime.now();
    final list = c.incidents.where(_match).toList();

    // Nhóm theo ngày, giữ thứ tự mới nhất trước.
    final groups = <DateTime, List<AlertIncident>>{};
    for (final i in list) {
      final d = DateTime(i.startedAt.year, i.startedAt.month, i.startedAt.day);
      groups.putIfAbsent(d, () => []).add(i);
    }

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
        children: [
          const LargeTitle('Lịch sử'),
          const SizedBox(height: 14),
          SegmentedControl<_Filter>(
            options: const {
              _Filter.all: 'Tất cả',
              _Filter.fall: 'Ngã',
              _Filter.still: 'Không cử động',
            },
            selected: _filter,
            onChanged: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: 22),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
              child: Column(
                children: [
                  IconTile(
                      icon: Icons.history_rounded,
                      size: 52,
                      radius: 16,
                      iconSize: 28,
                      bg: t.tile,
                      fg: t.textSub),
                  const SizedBox(height: 14),
                  Text('Chưa có sự cố nào',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600, color: t.text)),
                  const SizedBox(height: 4),
                  Text('Khi có cảnh báo, lịch sử sẽ hiện ở đây.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: t.textSub)),
                ],
              ),
            )
          else
            for (final e in groups.entries) ...[
              GroupSection(
                header: fmtDayHeader(e.key, now),
                children: [for (final i in e.value) _row(context, i)],
              ),
              const SizedBox(height: 18),
            ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AlertIncident i) {
    final t = context.tokens;
    final col = incidentColors(context, i.kind);
    final unconfirmed = i.kind != AlertKind.resumed && !i.acknowledged;
    // Chỉ nhắc khi chưa xác nhận để dòng gọn.
    final sub = unconfirmed ? '${incidentSource(i)} · Chưa xác nhận' : incidentSource(i);
    return ListRow(
      leading: IconTile(icon: incidentIcon(i.kind), bg: col.bg, fg: col.fg),
      title: incidentTitle(i),
      subtitle: sub,
      subtitleColor: unconfirmed ? t.warnText : null,
      trailing: Text(fmtHm(i.startedAt),
          style: TextStyle(fontSize: 14, color: t.textSub, fontFeatures: AppText.tabular)),
      showChevron: false,
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => IncidentDetailPage(incident: i)),
      ),
    );
  }
}
