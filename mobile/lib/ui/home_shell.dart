import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fusion/alert_models.dart';
import '../services/monitor_engine.dart';
import '../state/app_controller.dart';
import 'alarm_screen.dart';
import 'camera_tab.dart';
import 'events_tab.dart';
import 'settings_tab.dart';
import 'theme.dart';
import 'wearable_tab.dart';

/// Khung chính: 4 tab + chip sức khỏe kênh; tự mở màn báo động khi có sự cố.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  String? _shownId;
  bool _alarmOpen = false;

  static const _titles = ['Vòng đeo', 'Camera AI', 'Nhật ký', 'Cài đặt & SOS'];

  void _maybeShowAlarm(AppController c) {
    final r = c.ringing;
    if (r == null || _alarmOpen || _shownId == r.id) return;
    _shownId = r.id;
    _alarmOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const AlarmScreen(),
      ));
      _alarmOpen = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    _maybeShowAlarm(c);
    final tab = c.requestedTab;
    if (tab != null) {
      c.requestedTab = null;
      _index = tab;
    }
    final pages = <Widget>[
      const WearableTab(),
      const CameraTab(),
      const EventsTab(),
      const SettingsTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _HealthChips(health: c.health),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.watch_outlined), label: 'Vòng đeo'),
          NavigationDestination(icon: Icon(Icons.videocam_outlined), label: 'Camera AI'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Nhật ký'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Cài đặt & SOS'),
        ],
      ),
    );
  }
}

class _HealthChips extends StatelessWidget {
  const _HealthChips({required this.health});

  final ChannelHealth health;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final ch in AlertChannel.values)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Tooltip(
              message: '${ch.label}: ${health.of(ch) ? 'đang kết nối' : 'không có tín hiệu'}',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (health.of(ch) ? colors.ok : colors.muted).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  ch.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: health.of(ch) ? colors.ok : colors.muted,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
