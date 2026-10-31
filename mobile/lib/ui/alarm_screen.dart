import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fusion/alert_models.dart';
import '../state/app_controller.dart';
import 'widgets/common.dart';

/// Màn hình báo động toàn màn hình; chỉ thoát khi đã xác nhận.
class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  AlertIncident? _last;
  bool _popped = false;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final inc = c.ringing ?? _last;
    if (c.ringing != null) _last = c.ringing;
    if (c.ringing == null && !_popped) {
      _popped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
    }
    const bg = Color(0xFFB71C1C);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: inc == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: _Details(incident: inc),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.white, foregroundColor: bg),
                          onPressed: () async {
                            final ok = await c.callSos();
                            if (!ok && context.mounted) {
                              showSnack(context, 'Không mở được trình gọi điện.');
                            }
                          },
                          icon: const Icon(Icons.call),
                          label: const Text('GỌI CẤP CỨU / NGƯỜI THÂN NGAY',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white, width: 2)),
                          onPressed: () => c.acknowledge(inc.id),
                          icon: const Icon(Icons.volume_off),
                          label: const Text('ĐÃ KIỂM TRA — TẮT CHUÔNG',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.incident});

  final AlertIncident incident;

  @override
  Widget build(BuildContext context) {
    final i = incident;
    const white = TextStyle(color: Colors.white);
    final lines = <String>[
      if (i.deviceIds.isNotEmpty) 'Thiết bị: ${i.deviceIds.values.join(', ')}',
      if (i.impactG != null) 'Lực va chạm: ${i.impactG!.toStringAsFixed(1)} g',
      if (i.cameraConfidence != null)
        'Độ tin cậy camera: ${(i.cameraConfidence! * 100).round()}%',
      if (i.kind == AlertKind.inactive && i.stillMinutes != null)
        'Bất động: ${i.stillMinutes!.round()} phút',
      'Thời gian: ${fmtDateTime(i.startedAt)}',
      'Kênh đến đầu tiên: ${i.firstChannel.label}',
      if (i.arrivals.isNotEmpty)
        'Các kênh: ${i.arrivals.entries.map((e) => '${e.key.label} +${e.value.inMilliseconds} ms').join(' · ')}',
    ];
    return Column(
      children: [
        const SizedBox(height: 12),
        const Icon(Icons.warning_amber_rounded, size: 120, color: Colors.white),
        const SizedBox(height: 12),
        Text(
          i.label,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(l, textAlign: TextAlign.center, style: white.copyWith(fontSize: 16)),
          ),
      ],
    );
  }
}
