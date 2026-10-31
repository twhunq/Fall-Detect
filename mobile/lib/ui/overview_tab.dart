import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fusion/alert_models.dart';
import '../core/presence.dart';
import '../state/app_controller.dart';
import 'alarm_screen.dart';
import 'camera_live_page.dart';
import 'incident_detail_page.dart';
import 'settings/camera_settings_page.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/incident_ui.dart';
import 'widgets/mjpeg_view.dart';

/// Tab "Tổng quan": trạng thái an toàn, camera, thiết bị và sự cố gần nhất.
class OverviewTab extends StatefulWidget {
  const OverviewTab({
    super.key,
    this.active = true,
    this.onSeeAll,
    this.onOpenSettings,
  });

  /// false khi tab đang ẩn (tạm dừng luồng camera).
  final bool active;
  final VoidCallback? onSeeAll;
  final VoidCallback? onOpenSettings;

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Làm mới các mốc thời gian tương đối.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _cameraName(AppController c) {
    final id = c.connectedCameraId ??
        (c.settings.pairedCameras.isNotEmpty ? c.settings.pairedCameras.keys.first : null);
    if (id == null || id.isEmpty) return 'Camera';
    return id.startsWith('CBC-') ? 'Camera ${id.substring(4)}' : id;
  }

  static bool _cameraActive(AppController c, DateTime now) {
    if (c.cameraConnected && c.cameraAuthenticated) return true;
    final a = c.lastAlive;
    return a != null && now.difference(a).inSeconds <= 90;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final t = context.tokens;
    final now = DateTime.now();
    final streamUri = c.cameraInfo?.streamUri;
    final hasCamera = c.settings.pairedCameras.isNotEmpty || streamUri != null;
    final camActive = _cameraActive(c, now);
    final latest = c.incidents.isEmpty ? null : c.incidents.first;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
        children: [
          _Hero(c: c, now: now, cameraActive: hasCamera && camActive, latest: latest,
              onOpenSettings: widget.onOpenSettings),
          const SizedBox(height: 22),
          if (hasCamera) ...[
            _CameraBlock(
              uri: streamUri,
              name: _cameraName(c),
              active: widget.active,
            ),
            const SizedBox(height: 22),
          ],
          _DevicesGroup(c: c, now: now, hasCamera: hasCamera, camActive: camActive),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Gần đây',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: t.text)),
                ),
                TextButton(
                  onPressed: widget.onSeeAll,
                  child: const Text('Xem tất cả'),
                ),
              ],
            ),
          ),
          GroupSection(children: [
            if (latest == null)
              const ListRow(title: 'Chưa có sự cố nào', minHeight: 56)
            else
              _recentRow(context, latest, now),
          ]),
        ],
      ),
    );
  }

  Widget _recentRow(BuildContext context, AlertIncident i, DateTime now) {
    final col = incidentColors(context, i.kind);
    final status = i.kind == AlertKind.resumed
        ? ''
        : (i.acknowledged ? ' · Đã xử lý' : ' · Chưa xác nhận');
    return ListRow(
      leading: IconTile(icon: incidentIcon(i.kind), bg: col.bg, fg: col.fg),
      title: incidentTitle(i),
      subtitle: '${fmtDayHm(i.startedAt, now)}$status',
      subtitleColor: (!i.acknowledged && i.kind != AlertKind.resumed)
          ? context.tokens.warnText
          : null,
      onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => IncidentDetailPage(incident: i),
      )),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.c,
    required this.now,
    required this.cameraActive,
    required this.latest,
    this.onOpenSettings,
  });

  final AppController c;
  final DateTime now;
  final bool cameraActive;
  final AlertIncident? latest;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = c.personName;
    final w = c.wearable;
    final presence = c.wearablePresence;
    final last = c.wearableLastSeen;

    IconData icon;
    Color bg;
    Color fg;
    String title;
    Widget? body;
    String? bodyText;
    var titleStyle = AppText.hero;

    if (c.ringing != null || (w != null && w.alarmActive)) {
      icon = Icons.warning_amber_rounded;
      bg = t.badTint;
      fg = t.bad;
      title = '$name có thể đã ngã';
      titleStyle = AppText.largeTitle;
      body = Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: t.bad, foregroundColor: Colors.white),
            onPressed: () {
              if (c.ringing != null) {
                Navigator.of(context).push<void>(MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => const AlarmScreen(),
                ));
              } else if (latest != null) {
                Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) => IncidentDetailPage(incident: latest!),
                ));
              }
            },
            child: const Text('Mở cảnh báo'),
          ),
        ),
      );
    } else if (w != null && w.inactive) {
      icon = Icons.timer_outlined;
      bg = t.warnTint;
      fg = t.warnText;
      final m = (w.stillSec ~/ 60).clamp(1, 100000);
      title = '$name không cử động $m phút';
    } else if (presence == WearablePresence.offline) {
      icon = Icons.wifi_off_rounded;
      bg = t.warnTint;
      fg = t.warnText;
      title = 'Mất tín hiệu từ vòng đeo';
      final when = last == null
          ? ''
          : 'Lần cuối nhận được lúc ${fmtHm(last)}, cách đây ${fmtSpan(now.difference(last))}. ';
      bodyText = '${when}Hãy kiểm tra vòng đeo còn pin và $name vẫn ở trong vùng Wi-Fi.';
      if (cameraActive) {
        body = Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.verified_user_outlined, size: 18, color: t.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Camera vẫn đang theo dõi.',
                    style: TextStyle(fontSize: 14, height: 20 / 14, color: t.textStrong)),
              ),
            ],
          ),
        );
      }
    } else if (presence == WearablePresence.unknown) {
      icon = Icons.sync_rounded;
      bg = t.tile;
      fg = t.textStrong;
      title = 'Đang kết nối…';
      bodyText = 'Chưa nhận được dữ liệu từ vòng đeo.';
      body = Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 44)),
          onPressed: onOpenSettings,
          child: const Text('Kiểm tra cài đặt'),
        ),
      );
    } else {
      icon = Icons.verified_user_rounded;
      bg = t.primaryTint;
      fg = t.primary;
      title = '$name đang an toàn';
      final act = activityLabel(w?.activity);
      bodyText = [
        ?act,
        if (last != null) 'cập nhật ${fmtRelative(last, now)}',
      ].join(' · ');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconTile(icon: icon, bg: bg, fg: fg, size: 52, radius: 16, iconSize: 28),
              if (presence == WearablePresence.online)
                Row(
                  children: [
                    StatusDot(t.ok),
                    const SizedBox(width: 6),
                    Text('Đang theo dõi',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500, color: t.textSub)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: titleStyle.copyWith(color: t.text)),
          if (bodyText != null && bodyText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(bodyText,
                style: TextStyle(fontSize: 16, height: 22 / 16, color: t.textSub)),
          ],
          if (body != null) ...[const SizedBox(height: 8), body],
        ],
      ),
    );
  }
}

class _CameraBlock extends StatelessWidget {
  const _CameraBlock({required this.uri, required this.name, required this.active});

  final Uri? uri;
  final String name;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: uri == null
            ? const ColoredBox(
                color: Color(0xFF1C2535),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_rounded, size: 30, color: Color(0xFF8C97AB)),
                      SizedBox(height: 8),
                      Text('Chỉ xem được khi cùng Wi-Fi với camera',
                          style: TextStyle(fontSize: 13, color: Color(0xFF8C97AB))),
                    ],
                  ),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  MjpegView(uri: uri!, label: name, active: active, showExpandIcon: true),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                          builder: (_) => CameraLivePage(uri: uri!, name: name),
                        )),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DevicesGroup extends StatelessWidget {
  const _DevicesGroup({
    required this.c,
    required this.now,
    required this.hasCamera,
    required this.camActive,
  });

  final AppController c;
  final DateTime now;
  final bool hasCamera;
  final bool camActive;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final presence = c.wearablePresence;
    final last = c.wearableLastSeen;
    String sub;
    Color dot;
    switch (presence) {
      case WearablePresence.online:
        sub = 'Đang kết nối';
        dot = t.ok;
      case WearablePresence.offline:
        sub = last == null ? 'Mất kết nối' : 'Mất kết nối · ${fmtSpan(now.difference(last))}';
        dot = t.warn;
      case WearablePresence.unknown:
        sub = 'Chưa có dữ liệu';
        dot = t.chevron;
    }
    final low = c.wearable?.batteryLow == true;
    final pct = c.batteryPercent;
    Widget? battery;
    if (c.onUsbPower) {
      battery = _Battery(Icons.battery_charging_full_rounded, 'Cắm nguồn', t.textStrong);
    } else if (pct != null) {
      final color = low ? t.bad : t.textStrong;
      final icon = low
          ? Icons.battery_alert_rounded
          : pct >= 60
              ? Icons.battery_full_rounded
              : Icons.battery_4_bar_rounded;
      battery = _Battery(icon, '$pct%', color);
    }
    final camName = _OverviewTabState._cameraName(c);
    return GroupSection(children: [
      ListRow(
        leading: const IconTile(icon: Icons.watch_rounded),
        title: 'Vòng đeo',
        subtitle: sub,
        dot: dot,
        trailing: battery,
      ),
      if (hasCamera)
        ListRow(
          leading: const IconTile(icon: Icons.videocam_rounded),
          title: camName,
          subtitle: camActive ? 'Đang theo dõi' : 'Chưa kết nối',
          dot: camActive ? t.ok : t.chevron,
        )
      else
        ListRow(
          leading: IconTile(icon: Icons.add_rounded, bg: t.primaryTint, fg: t.primary),
          title: 'Thêm camera',
          accent: true,
          minHeight: 64,
          onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const CameraSettingsPage())),
        ),
    ]);
  }
}

class _Battery extends StatelessWidget {
  const _Battery(this.icon, this.text, this.color);

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
                fontFeatures: AppText.tabular)),
      ],
    );
  }
}
