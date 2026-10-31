import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'platform/alarm_player.dart';
import 'platform/background_service.dart';
import 'platform/monitor_backend.dart';
import 'platform/notifications.dart';
import 'platform/permissions.dart';
import 'services/app_settings.dart';
import 'services/camera_ble_service.dart';
import 'services/firebase_auth_client.dart';
import 'services/firebase_rtdb_client.dart';
import 'services/monitor_engine.dart';
import 'services/secure_store.dart';
import 'state/app_controller.dart';

const String _kLocalMode = 'app.localMode';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final secure = SecureStore();
  final settings = await AppSettings.load(secure);
  final tokens =
      TokenManager(FirebaseAuthClient(apiKey: settings.firebaseApiKey), secure);
  await tokens.restore();
  final prefs = await SharedPreferences.getInstance();

  final useService = !kIsWeb && Platform.isAndroid && settings.useBackgroundService;
  Future<MonitorBackend> makeBackend(bool service) async {
    if (service) {
      await AppBackgroundService.configure();
      return ServiceMonitorBackend();
    }
    return LocalMonitorBackend(MonitorEngine(settings: settings, tokens: tokens));
  }

  final backend = await makeBackend(useService);

  final notifications = AlertNotifications();
  late final AppController controller;
  await notifications.init(onTap: (_) => unawaited(controller.handleNotificationOpen()));

  controller = AppController(
    backend: backend,
    settings: settings,
    tokens: tokens,
    rtdb: FirebaseRtdbClient(tokens, databaseUrl: settings.firebaseDatabaseUrl),
    ble: CameraBleService(),
    alarm: AlarmPlayer(),
    keepAlive: KeepAlivePlayer(),
    notifier: notifications,
    permissions: const SystemPermissions(),
    localMode: prefs.getBool(_kLocalMode) ?? false,
    persistLocalMode: (v) async {
      await prefs.setBool(_kLocalMode, v);
    },
    backendFactory: makeBackend,
  );

  runApp(BaoNgaApp(controller: controller));
  await controller.start();

  // Mở bằng bấm thông báo / full-screen intent khi app chưa chạy.
  try {
    final launch = await FlutterLocalNotificationsPlugin().getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      await controller.handleNotificationOpen();
    }
  } catch (e) {
    debugPrint('getNotificationAppLaunchDetails loi: $e');
  }

  // Xin quyền thông báo sau khi giao diện đã lên.
  unawaited(Future<void>.delayed(const Duration(seconds: 2), () async {
    await const SystemPermissions().requestNotifications();
  }));
}
