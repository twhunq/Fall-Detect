import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_controller.dart';
import 'alarm_screen.dart';
import 'history_tab.dart';
import 'overview_tab.dart';
import 'settings/wearable_settings_page.dart';
import 'settings_tab.dart';
import 'theme.dart';

/// Khung chính: 3 tab (Tổng quan / Lịch sử / Cài đặt); tự mở màn báo động khi có sự cố.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  String? _shownId;
  bool _alarmOpen = false;

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

  void _maybeOpenWearableSetup(AppController c) {
    if (!c.requestWearableSetup) return;
    c.requestWearableSetup = false;
    _index = 2;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const WearableSettingsPage()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final t = context.tokens;
    _maybeShowAlarm(c);
    final tab = c.requestedTab;
    if (tab != null) {
      c.requestedTab = null;
      _index = tab.clamp(0, 2);
    }
    _maybeOpenWearableSetup(c);
    final pages = <Widget>[
      OverviewTab(
        active: _index == 0,
        onSeeAll: () => setState(() => _index = 1),
        onOpenSettings: () => setState(() => _index = 2),
      ),
      const HistoryTab(),
      const SettingsTab(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(top: BorderSide(color: t.line, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Tổng quan',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded),
              selectedIcon: Icon(Icons.history_rounded),
              label: 'Lịch sử',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Cài đặt',
            ),
          ],
        ),
      ),
    );
  }
}
