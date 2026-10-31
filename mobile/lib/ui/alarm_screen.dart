import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fusion/alert_models.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/mjpeg_view.dart';

/// Màn hình báo động toàn màn hình; chỉ thoát khi đã xác nhận.
class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  AlertIncident? _last;
  bool _popped = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

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
    const bg = AppTokens.alarmBg;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: inc == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: _Details(
                              incident: inc,
                              name: c.personName,
                              streamUri: c.cameraInfo?.streamUri,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: bg,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            textStyle: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                          onPressed: () async {
                            final ok = await c.callSos();
                            if (!ok && context.mounted) {
                              showSnack(context, 'Không mở được trình gọi điện.');
                            }
                          },
                          icon: const Icon(Icons.call_rounded),
                          label: const Text('Gọi cấp cứu 115'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.14),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            textStyle: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 17,
                                fontWeight: FontWeight.w600),
                          ),
                          onPressed: () => c.acknowledge(inc.id),
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          label: const Text('Đã kiểm tra, tắt chuông'),
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
  const _Details({required this.incident, required this.name, required this.streamUri});

  final AlertIncident incident;
  final String name;
  final Uri? streamUri;

  @override
  Widget build(BuildContext context) {
    final i = incident;
    final now = DateTime.now();
    final String title;
    if (i.kind == AlertKind.inactive) {
      final m = i.stillMinutes?.round();
      title = m == null || m <= 0 ? '$name không cử động' : '$name không cử động $m phút';
    } else {
      title = '$name có thể đã ngã';
    }
    final w = i.origins.contains(AlertOrigin.wearable);
    final cam = i.origins.contains(AlertOrigin.camera);
    final chip = (w && cam)
        ? 'Vòng đeo và camera cùng xác nhận'
        : (cam ? 'Phát hiện bởi camera' : 'Phát hiện bởi vòng đeo');
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
          child: const Icon(Icons.warning_amber_rounded, size: 40, color: Colors.white),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 36,
              height: 42 / 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.72,
              color: Colors.white),
        ),
        const SizedBox(height: 10),
        Text(
          'Lúc ${fmtHm(i.startedAt)} · ${fmtRelative(i.startedAt, now)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, height: 24 / 17, color: Color(0xFFFFE4E1)),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(chip,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ],
          ),
        ),
        if (streamUri != null) ...[
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 196,
              width: double.infinity,
              child: MjpegView(
                uri: streamUri!,
                label: 'Camera · trực tiếp',
                placeholderColor: const Color(0xFFE9B3AC),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
