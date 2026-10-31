import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../core/fusion/alert_models.dart';
import '../services/app_settings.dart';
import '../services/firebase_auth_client.dart';
import '../services/monitor_engine.dart';
import '../services/secure_store.dart';
import 'notifications.dart';

/// Foreground service giam sat nen. Chi Android; tren iOS moi ham la no-op tra false.
class AppBackgroundService {
  const AppBackgroundService._();

  static const int notificationId = 4711;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<void> configure() async {
    if (!_supported) return;
    try {
      // Kenh thong bao phai ton tai truoc khi configure().
      await AlertNotifications().init();
      await FlutterBackgroundService().configure(
        androidConfiguration: AndroidConfiguration(
          onStart: backgroundServiceMain,
          autoStart: false,
          autoStartOnBoot: false,
          isForegroundMode: true,
          notificationChannelId: kServiceChannelId,
          initialNotificationTitle: 'Báo Ngã IoT đang giám sát',
          initialNotificationContent: 'Đang theo dõi thiết bị đeo và camera',
          foregroundServiceNotificationId: notificationId,
          foregroundServiceTypes: [AndroidForegroundType.connectedDevice],
        ),
        iosConfiguration: IosConfiguration(autoStart: false),
      );
    } catch (e) {
      debugPrint('BackgroundService.configure loi: $e');
    }
  }

  static Future<bool> start() async {
    if (!_supported) return false;
    try {
      return await FlutterBackgroundService().startService();
    } catch (e) {
      debugPrint('BackgroundService.start loi: $e');
      return false;
    }
  }

  static Future<bool> stop() async {
    if (!_supported) return false;
    try {
      FlutterBackgroundService().invoke('stop');
      return true;
    } catch (e) {
      debugPrint('BackgroundService.stop loi: $e');
      return false;
    }
  }

  static Future<bool> isRunning() async {
    if (!_supported) return false;
    try {
      return await FlutterBackgroundService().isRunning();
    } catch (_) {
      return false;
    }
  }
}

Future<void> Function()? _stopHook;

/// Diem vao cua isolate nen (Android).
@pragma('vm:entry-point')
Future<void> backgroundServiceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  service.on('stop').listen((_) async {
    try {
      await _stopHook?.call();
    } catch (e) {
      debugPrint('service stop loi: $e');
    }
    await service.stopSelf();
  });

  try {
    await runMonitorInBackground(service);
  } catch (e, st) {
    debugPrint('backgroundServiceMain loi: $e\n$st');
  }
}

/// Tom tat suc khoe kenh cho thong bao co dinh.
String healthSummary(ChannelHealth h) {
  String f(String n, bool v) => '$n ${v ? '●' : '○'}';
  return '${f('UDP', h.udp)}  ${f('BLE', h.ble)}  ${f('Cloud', h.cloud)}  ${f('LAN', h.lan)}';
}

String incidentBody(AlertIncident i) {
  final parts = <String>[];
  if (i.deviceIds.isNotEmpty) parts.add(i.deviceIds.values.join(', '));
  if (i.impactG != null) parts.add('va chạm ${i.impactG!.toStringAsFixed(1)} g');
  if (i.cameraConfidence != null) {
    parts.add('camera ${(i.cameraConfidence! * 100).round()}%');
  }
  if (i.stillMinutes != null && i.kind == AlertKind.inactive) {
    parts.add('bất động ${i.stillMinutes!.round()} phút');
  }
  parts.add('kênh ${i.firstChannel.label}');
  return parts.join(' · ');
}

/// Chay MonitorEngine trong isolate nen va noi voi UI qua invoke()/on().
///
/// UI -> service: 'signal', 'ack', 'reload', 'sync', 'clear', 'stop'.
/// service -> UI: 'result', 'status', 'health', 'snapshot'.
Future<void> runMonitorInBackground(ServiceInstance service) async {
  final notifications = AlertNotifications();
  await notifications.init();

  final secure = SecureStore();
  final settings = await AppSettings.load(secure);
  final tokens = TokenManager(
      FirebaseAuthClient(apiKey: settings.firebaseApiKey), secure);
  await tokens.restore();
  final engine = MonitorEngine(settings: settings, tokens: tokens);

  void guard(String what, void Function() f) {
    try {
      f();
    } catch (e, st) {
      debugPrint('service $what loi: $e\n$st');
    }
  }

  Map<String, dynamic> snapshot() => {
        'recent': engine.recent.map((i) => i.toJson()).toList(),
        'status': engine.lastStatus == null
            ? null
            : MonitorEngine.statusToJson(engine.lastStatus!),
        'health': MonitorEngine.healthToJson(engine.health),
        'baseUrl': engine.wearableBaseUrl,
      };

  void updateNotification(ChannelHealth h) {
    if (service is AndroidServiceInstance) {
      unawaited(service.setForegroundNotificationInfo(
        title: 'Báo Ngã IoT đang giám sát',
        content: healthSummary(h),
      ));
    }
  }

  engine.results.listen((r) {
    guard('result', () {
      service.invoke('result', MonitorEngine.resultToJson(r));
      if (r.shouldRing) {
        unawaited(notifications.showAlarm(
          id: notificationIdFor(r.incident.id),
          title: r.incident.label,
          body: incidentBody(r.incident),
          payload: r.incident.id,
        ));
      }
    });
  });
  engine.wearableStatus.listen((s) =>
      guard('status', () => service.invoke('status', MonitorEngine.statusToJson(s))));
  engine.channelHealth.listen((h) => guard('health', () {
        service.invoke('health', MonitorEngine.healthToJson(h));
        updateNotification(h);
      }));

  service.on('signal').listen((e) => guard('signal', () {
        if (e == null) return;
        final s = MonitorEngine.signalFromJson(e);
        if (s != null) engine.ingest(s);
      }));
  service.on('ack').listen((e) => guard('ack', () {
        final id = e?['id'] as String?;
        if (id == null) return;
        engine.acknowledge(id);
        unawaited(notifications.cancel(notificationIdFor(id)));
        service.invoke('snapshot', snapshot());
      }));
  service.on('clear').listen((_) async {
    try {
      await engine.clearHistory();
      service.invoke('snapshot', snapshot());
    } catch (e, st) {
      debugPrint('service clear loi: $e $st');
    }
  });
  service.on('sync').listen((_) => guard('sync', () {
        service.invoke('snapshot', snapshot());
      }));
  service.on('reload').listen((_) async {
    try {
      await settings.reload();
      await tokens.restore();
      await engine.applySettings();
      service.invoke('snapshot', snapshot());
    } catch (e, st) {
      debugPrint('service reload loi: $e\n$st');
    }
  });

  _stopHook = () async {
    await engine.stop();
  };

  await engine.start();
  updateNotification(engine.health);
  // Bao UI biet service da san sang (UI co the da gui 'sync' truoc khi isolate nay lang nghe).
  service.invoke('snapshot', snapshot());
}
