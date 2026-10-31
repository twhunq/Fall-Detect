import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fusion/alert_models.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'widgets/common.dart';

class EventsTab extends StatelessWidget {
  const EventsTab({super.key});

  Future<void> _clear(BuildContext context, AppController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa nhật ký?'),
        content: const Text('Toàn bộ lịch sử sự cố trên điện thoại sẽ bị xóa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok == true) await c.clearLog();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final list = c.incidents;
    if (list.isEmpty) {
      return Center(
        child: Text('Chưa có sự cố nào.',
            style: TextStyle(color: context.statusColors.muted)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: list.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _clear(context, c),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Xóa nhật ký'),
            ),
          );
        }
        return _IncidentCard(incident: list[i - 1]);
      },
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.incident});

  final AlertIncident incident;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final i = incident;
    final labelColor = i.multiSource
        ? colors.bad
        : (i.kind == AlertKind.resumed ? colors.ok : colors.warn);
    final origins = i.origins.map((o) => o == AlertOrigin.wearable ? 'Vòng đeo' : 'Camera AI').join(' + ');
    final metrics = <String>[
      if (i.impactG != null) 'Va chạm ${i.impactG!.toStringAsFixed(1)} g',
      if (i.cameraConfidence != null) 'Camera ${(i.cameraConfidence! * 100).round()}%',
      if (i.stillMinutes != null) 'Bất động ${i.stillMinutes!.toStringAsFixed(1)} phút',
    ];
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: i.multiSource ? colors.bad : Theme.of(context).colorScheme.outline,
            width: i.multiSource ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i.label,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: labelColor, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(fmtDateTime(i.startedAt), style: TextStyle(color: colors.muted)),
            const SizedBox(height: 6),
            InfoRow('Nguồn', origins),
            InfoRow('Kênh đầu tiên', i.firstChannel.label),
            if (i.arrivals.isNotEmpty)
              InfoRow(
                  'Các kênh',
                  (i.arrivals.entries.toList()
                        ..sort((a, b) => a.value.compareTo(b.value)))
                      .map((e) => '${e.key.label} +${e.value.inMilliseconds} ms')
                      .join(' · ')),
            if (i.cloudLatency != null)
              InfoRow('Độ trễ cloud', '${i.cloudLatency!.inMilliseconds} ms'),
            if (metrics.isNotEmpty) InfoRow('Số đo', metrics.join(' · ')),
            InfoRow(
                'Xác nhận',
                i.acknowledged
                    ? 'Đã xác nhận${i.acknowledgedAt == null ? '' : ' lúc ${fmtClock(i.acknowledgedAt!)}'}'
                    : 'Chưa xác nhận',
                color: i.acknowledged ? colors.ok : colors.warn),
          ],
        ),
      ),
    );
  }
}
