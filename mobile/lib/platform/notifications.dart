import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Id kenh thong bao (kenh 'baonga_service' dung cho foreground service).
const String kAlarmChannelId = 'baonga_alarm';
const String kServiceChannelId = 'baonga_service';

/// Id thong bao on dinh theo id su co (dung chung giua isolate UI va isolate nen).
int notificationIdFor(String incidentId) => incidentId.hashCode & 0x3FFFFFFF;

abstract class AlertNotifier {
  Future<void> init({void Function(String? payload)? onTap});
  Future<bool> requestPermissions();
  Future<void> showAlarm({
    required int id,
    required String title,
    required String body,
    String? payload,
  });
  Future<void> cancel(int id);
}

/// Thong bao canh bao. Dung duoc ca trong isolate cua background service
/// (moi isolate co instance plugin rieng, goi init() truoc khi dung).
class AlertNotifications implements AlertNotifier {
  AlertNotifications({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _inited = false;

  /// Goi khi nguoi dung bam vao thong bao (payload co the null).
  void Function(String? payload)? onTap;

  @override
  Future<void> init({void Function(String? payload)? onTap}) async {
    if (onTap != null) this.onTap = onTap;
    if (_inited) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => this.onTap?.call(r.payload),
      );
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android?.createNotificationChannel(
          AndroidNotificationChannel(
            kAlarmChannelId,
            'Cảnh báo té ngã',
            description: 'Cảnh báo khẩn khi phát hiện té ngã',
            importance: Importance.max,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('alarm'),
            enableVibration: true,
            vibrationPattern: _vibration,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            // bypassDnd can quyen ACCESS_NOTIFICATION_POLICY do nguoi dung cap
            // (chua khai bao) nen de false.
            bypassDnd: false,
          ),
        );
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            kServiceChannelId,
            'Dịch vụ giám sát',
            description: 'Thông báo cố định khi app đang giám sát nền',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
            showBadge: false,
          ),
        );
      }
      _inited = true;
    } catch (e) {
      debugPrint('AlertNotifications.init loi: $e');
    }
  }

  static final Int64List _vibration =
      Int64List.fromList([0, 700, 400, 700, 400, 700]);

  /// Xin quyen thong bao (Android 13+, iOS). Khong nem loi.
  @override
  Future<bool> requestPermissions() async {
    try {
      await init();
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final ok = await android?.requestNotificationsPermission() ?? false;
        try {
          await android?.requestFullScreenIntentPermission();
        } catch (_) {}
        return ok;
      }
      if (Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(
              alert: true,
              sound: true,
              badge: true,
            ) ??
            false;
      }
    } catch (e) {
      debugPrint('requestPermissions loi: $e');
    }
    return false;
  }

  @override
  Future<void> showAlarm({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        kAlarmChannelId,
        'Cảnh báo té ngã',
        channelDescription: 'Cảnh báo khẩn khi phát hiện té ngã',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('alarm'),
        enableVibration: true,
        vibrationPattern: _vibration,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        visibility: NotificationVisibility.public,
        ticker: title,
        // FLAG_INSISTENT: lap am thanh/rung cho toi khi thong bao bi huy (xac nhan).
        additionalFlags: Int32List.fromList(<int>[4]),
        actions: const [
          AndroidNotificationAction(
            'open_alarm',
            'Mở màn hình báo động',
            showsUserInterface: true,
            cancelNotification: false,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('showAlarm loi: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('cancel loi: $e');
    }
  }
}
