import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fusion/alert_models.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/incident_ui.dart';

/// Chi tiết một sự cố; thông tin kỹ thuật thu gọn mặc định.
class IncidentDetailPage extends StatefulWidget {
  const IncidentDetailPage({super.key, required this.incident});

  final AlertIncident incident;

  @override
  State<IncidentDetailPage> createState() => _IncidentDetailPageState();
}

class _IncidentDetailPageState extends State<IncidentDetailPage> {
  bool _open = false;

  static String _channel(AlertChannel ch) {
    switch (ch) {
      case AlertChannel.udp:
        return 'Wi-Fi nội bộ';
      case AlertChannel.ble:
        return 'Bluetooth';
      case AlertChannel.cloud:
        return 'Cloud';
      case AlertChannel.lan:
        return 'Hỏi trực tiếp vòng đeo';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final t = context.tokens;
    final now = DateTime.now();
    // Lấy bản mới nhất theo id (đối tượng có thể được thay khi đồng bộ).
    final i = c.incidents.where((x) => x.id == widget.incident.id).firstOrNull ??
        widget.incident;
    final col = incidentColors(context, i.kind);
    final ackText = i.acknowledged
        ? (i.acknowledgedAt != null
            ? 'Đã xác nhận lúc ${fmtHm(i.acknowledgedAt!)}'
            : 'Đã xác nhận')
        : 'Chưa xác nhận';
    final techRows = <Widget>[
      if (i.impactG != null)
        KeyValueRow('Lực va chạm', '${i.impactG!.toStringAsFixed(1).replaceAll('.', ',')} g',
            prominent: true),
      if (i.cameraConfidence != null)
        KeyValueRow('Camera chắc chắn', '${(i.cameraConfidence! * 100).round()}%',
            prominent: true),
      if (i.kind == AlertKind.inactive && i.stillMinutes != null)
        KeyValueRow('Bất động', '${i.stillMinutes!.round()} phút', prominent: true),
      KeyValueRow('Đến đầu tiên qua', _channel(i.firstChannel), prominent: true),
      if (i.arrivals.isNotEmpty)
        KeyValueRow(
          'Các kênh',
          '${i.arrivals.entries.map((e) => '${e.key.label} +${e.value.inMilliseconds}').join(' · ')} ms',
          prominent: true,
          small: true,
        ),
      if (i.cloudLatency != null)
        KeyValueRow('Độ trễ cloud', '${i.cloudLatency!.inMilliseconds} ms', prominent: true),
    ];
    return SubPage(
      backLabel: 'Quay lại',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              IconTile(
                  icon: incidentIcon(i.kind),
                  bg: col.bg,
                  fg: col.fg,
                  size: 52,
                  radius: 16,
                  iconSize: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(incidentTitle(i),
                        style: TextStyle(
                            fontSize: 26,
                            height: 32 / 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.52,
                            color: t.text)),
                    Text(fmtDayHm(i.startedAt, now),
                        style: TextStyle(fontSize: 15, color: t.textSub)),
                  ],
                ),
              ),
            ],
          ),
        ),
        GroupSection(children: [
          KeyValueRow('Phát hiện bởi', incidentSource(i), prominent: true),
          KeyValueRow('Độ chắc chắn', i.multiSource ? 'Cao' : 'Một thiết bị phát hiện',
              prominent: true),
          KeyValueRow('Trạng thái', ackText,
              prominent: true,
              valueColor: i.acknowledged ? null : t.warnText),
        ]),
        if (!i.acknowledged && i.kind != AlertKind.resumed)
          FilledButton(
            onPressed: () => c.acknowledge(i.id),
            child: const Text('Xác nhận đã kiểm tra'),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Thông tin kỹ thuật',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: t.textStrong)),
                      ),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: Icon(Icons.expand_more_rounded, color: t.textStrong),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GroupSection(children: techRows),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ],
    );
  }
}
