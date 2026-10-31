import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bao_nga_iot/core/fusion/alert_models.dart';
import 'package:bao_nga_iot/core/protocol/ble_protocol.dart';
import 'package:bao_nga_iot/platform/alarm_player.dart';
import 'package:bao_nga_iot/platform/monitor_backend.dart';
import 'package:bao_nga_iot/platform/notifications.dart';
import 'package:bao_nga_iot/platform/permissions.dart';
import 'package:bao_nga_iot/services/app_settings.dart';
import 'package:bao_nga_iot/services/camera_ble_service.dart';
import 'package:bao_nga_iot/services/firebase_auth_client.dart';
import 'package:bao_nga_iot/services/firebase_rtdb_client.dart';
import 'package:bao_nga_iot/services/monitor_engine.dart';
import 'package:bao_nga_iot/services/secure_store.dart';
import 'package:bao_nga_iot/services/wearable_lan_service.dart';
import 'package:bao_nga_iot/state/app_controller.dart';
import 'package:bao_nga_iot/ui/alarm_screen.dart';
import 'package:bao_nga_iot/ui/home_shell.dart';
import 'package:bao_nga_iot/ui/overview_tab.dart';
import 'package:bao_nga_iot/ui/settings/camera_settings_page.dart';
import 'package:bao_nga_iot/ui/theme.dart';

// ---- Bản giả (không gọi plugin) ----

class FakeBackend implements MonitorBackend {
  final resultsCtl = StreamController<FusionResult>.broadcast();
  final statusCtl = StreamController<WearableStatus>.broadcast();
  final healthCtl = StreamController<ChannelHealth>.broadcast();
  final recentCtl = StreamController<void>.broadcast();
  final List<String> acked = [];
  final List<AlertSignal> ingested = [];

  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Stream<FusionResult> get results => resultsCtl.stream;
  @override
  Stream<WearableStatus> get status => statusCtl.stream;
  @override
  Stream<ChannelHealth> get health => healthCtl.stream;
  @override
  Stream<void> get recentChanged => recentCtl.stream;
  @override
  List<AlertIncident> get recent => const [];
  @override
  ChannelHealth get currentHealth => const ChannelHealth();
  @override
  WearableStatus? get lastStatus => null;
  @override
  String get wearableBaseUrl => '';
  @override
  bool get notifiesInBackground => false;
  @override
  void ingest(AlertSignal s) => ingested.add(s);
  @override
  Future<void> acknowledge(String id) async => acked.add(id);
  @override
  Future<void> reload() async {}
  @override
  Future<void> sync() async {}
  @override
  Future<void> clearHistory() async {}
  @override
  void setBleConnected(bool v) {}
}

class FakeSound implements AlarmSound {
  int starts = 0;
  int stops = 0;
  @override
  Future<void> start() async => starts++;
  @override
  Future<void> stop() async => stops++;
}

class FakeNotifier implements AlertNotifier {
  final List<int> cancelled = [];
  @override
  Future<void> init({void Function(String? payload)? onTap}) async {}
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<void> showAlarm({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {}
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

class FakePermissions implements PermissionService {
  @override
  Future<bool> requestBle() async => true;
  @override
  Future<bool> requestCamera() async => true;
  @override
  Future<bool> requestNotifications() async => true;
  @override
  Future<bool> requestIgnoreBatteryOptimizations() async => true;
  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;
}

class FakeCameraBleService extends CameraBleService {
  final alertsCtl = StreamController<BleAlertMessage>.broadcast();
  final connectedCtl = StreamController<bool>.broadcast();
  final authenticatedCtl = StreamController<bool>.broadcast();

  List<int>? lastAutoAuthKey;
  final List<String> connectedRemoteIds = [];
  int disconnectCalls = 0;
  bool authed = false;

  @override
  Stream<BleAlertMessage> get alerts => alertsCtl.stream;
  @override
  Stream<bool> get connected => connectedCtl.stream;
  @override
  Stream<bool> get authenticated => authenticatedCtl.stream;
  @override
  bool get isAuthenticated => authed;

  @override
  void setAutoAuthKey(List<int>? key) {
    lastAutoAuthKey = key;
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String remoteId) async {
    connectedRemoteIds.add(remoteId);
    authed = lastAutoAuthKey != null;
    connectedCtl.add(true);
    if (authed) authenticatedCtl.add(true);
  }

  @override
  Future<bool> authenticate(List<int> key) async {
    authed = true;
    authenticatedCtl.add(true);
    return true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    authed = false;
    connectedCtl.add(false);
    authenticatedCtl.add(false);
  }
}

class Harness {
  Harness(this.controller, this.backend, this.alarm, this.notifier);
  final AppController controller;
  final FakeBackend backend;
  final FakeSound alarm;
  final FakeNotifier notifier;
}

Future<Harness> makeHarness(WidgetTester tester, {DateTime Function()? clock}) async {
  late Harness h;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    final secure = SecureStore();
    final settings = await AppSettings.load(secure);
    final tokens = TokenManager(FirebaseAuthClient(), secure);
    final backend = FakeBackend();
    final alarm = FakeSound();
    final notifier = FakeNotifier();
    final controller = AppController(
      backend: backend,
      settings: settings,
      tokens: tokens,
      rtdb: FirebaseRtdbClient(tokens),
      ble: CameraBleService(),
      alarm: alarm,
      keepAlive: FakeSound(),
      notifier: notifier,
      permissions: FakePermissions(),
      isAndroid: true,
      isIOS: false,
      localMode: true,
      launcher: (_) async => true,
      clock: clock,
    );
    await controller.start();
    h = Harness(controller, backend, alarm, notifier);
  });
  addTearDown(h.controller.dispose);
  return h;
}

Widget wrap(AppController c, Widget child) => ChangeNotifierProvider<AppController>.value(
      value: c,
      child: MaterialApp(theme: AppTheme.light, darkTheme: AppTheme.dark, home: child),
    );

AlertIncident makeIncident({Set<AlertOrigin>? origins}) => AlertIncident(
      id: 'inc-1',
      kind: AlertKind.fall,
      startedAt: DateTime.now(),
      firstChannel: AlertChannel.udp,
      lastSignalAt: DateTime.now(),
      origins: origins ?? {AlertOrigin.wearable},
      arrivals: {AlertChannel.udp: Duration.zero, AlertChannel.cloud: const Duration(milliseconds: 12)},
      deviceIds: {AlertOrigin.wearable: 'baonga-01'},
      impactG: 3.2,
    );

Finder _navLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('HomeShell có 3 tab và chuyển được', (tester) async {
    _bigView(tester);
    final h = await makeHarness(tester);

    await tester.pumpWidget(wrap(h.controller, const HomeShell()));
    await tester.pump();

    for (final label in ['Tổng quan', 'Lịch sử', 'Cài đặt']) {
      expect(_navLabel(label), findsOneWidget);
    }
    expect(find.text('Chưa có sự cố nào'), findsOneWidget); // dòng "Gần đây"

    await tester.tap(_navLabel('Lịch sử'));
    await tester.pump();
    expect(find.text('Tất cả'), findsOneWidget);
    expect(find.text('Không cử động'), findsOneWidget);
    expect(find.text('Chưa có sự cố nào'), findsOneWidget);

    await tester.tap(_navLabel('Cài đặt'));
    await tester.pump();
    expect(find.text('Người được theo dõi'), findsOneWidget);
    expect(find.text('Chẩn đoán'), findsOneWidget);
    expect(find.byKey(const Key('sosPhone')), findsNothing);
  });

  testWidgets('Tổng quan: hiện "đang an toàn" khi vòng đeo online', (tester) async {
    _bigView(tester);
    final h = await makeHarness(tester);
    await tester.pumpWidget(wrap(h.controller, const Scaffold(body: OverviewTab())));
    await tester.pump();
    expect(find.textContaining('Đang kết nối…'), findsOneWidget); // chưa có dữ liệu

    h.backend.statusCtl.add(const WearableStatus(activity: 'ngoi', batteryMv: 3900));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('đang an toàn'), findsOneWidget);
    expect(find.textContaining('Đang ngồi'), findsOneWidget);
    expect(find.text('Đang theo dõi'), findsOneWidget);
  });

  testWidgets('Tổng quan: hiện "Mất tín hiệu" khi vòng đeo offline', (tester) async {
    _bigView(tester);
    var now = DateTime(2025, 10, 28, 10, 0);
    final h = await makeHarness(tester, clock: () => now);
    await tester.pumpWidget(wrap(h.controller, const Scaffold(body: OverviewTab())));
    await tester.pump();

    h.backend.statusCtl.add(const WearableStatus(batteryMv: 3900));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('đang an toàn'), findsOneWidget);

    now = now.add(const Duration(minutes: 12));
    await tester.pump(const Duration(seconds: 6)); // bộ đếm 5 s của tab làm mới giao diện
    expect(find.text('Mất tín hiệu từ vòng đeo'), findsOneWidget);
    expect(find.textContaining('Lần cuối nhận được lúc 10:00'), findsOneWidget);
    expect(find.textContaining('đang an toàn'), findsNothing);
  });

  testWidgets('AlarmScreen: tiêu đề, nút, nâng cấp đa nguồn, xác nhận', (tester) async {
    _bigView(tester);
    final h = await makeHarness(tester);

    final inc = makeIncident();
    h.backend.resultsCtl.add(FusionResult(FusionAction.newIncident, inc));
    await tester.pump();
    expect(h.controller.ringing?.id, 'inc-1');
    expect(h.alarm.starts, 1);

    await tester.pumpWidget(wrap(h.controller, const AlarmScreen()));
    await tester.pump();
    expect(find.text('Người thân có thể đã ngã'), findsOneWidget);
    expect(find.text('Phát hiện bởi vòng đeo'), findsOneWidget);
    expect(find.text('Gọi cấp cứu 115'), findsOneWidget);
    expect(find.text('Đã kiểm tra, tắt chuông'), findsOneWidget);

    // Camera xác nhận thêm: chip nâng cấp trực tiếp.
    inc.origins.add(AlertOrigin.camera);
    inc.deviceIds[AlertOrigin.camera] = 'CBC-ABCDEF';
    h.backend.resultsCtl.add(FusionResult(FusionAction.fused, inc));
    await tester.pump();
    await tester.pump();
    expect(find.text('Vòng đeo và camera cùng xác nhận'), findsOneWidget);

    await tester.tap(find.text('Đã kiểm tra, tắt chuông'));
    await tester.pump();
    expect(h.backend.acked, ['inc-1']);
    expect(h.alarm.stops, 1);
    expect(h.controller.ringing, isNull);
  });

  testWidgets('Cài đặt › Telegram: báo lỗi khi nhập 6 Chat ID', (tester) async {
    _bigView(tester);
    final h = await makeHarness(tester);

    await tester.pumpWidget(wrap(h.controller, const HomeShell()));
    await tester.pump();
    await tester.tap(_navLabel('Cài đặt'));
    await tester.pump();
    await tester.tap(find.text('Telegram'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('chatIds')), '1, 2, 3, 4, 5, 6');
    final save = find.byKey(const Key('saveSettings'));
    await tester.ensureVisible(save);
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    expect(find.text('Tối đa 5 Chat ID.'), findsOneWidget);
    expect(find.byKey(const Key('inactiveMin')), findsOneWidget);
  });

  testWidgets('Cài đặt › Chẩn đoán › Kết nối thủ công mở được', (tester) async {
    _bigView(tester);
    final h = await makeHarness(tester);

    await tester.pumpWidget(wrap(h.controller, const HomeShell()));
    await tester.pump();
    await tester.tap(_navLabel('Cài đặt'));
    await tester.pump();
    await tester.tap(find.text('Chẩn đoán'));
    await tester.pumpAndSettle();
    expect(find.text('Đường nhận cảnh báo'), findsOneWidget);
    await tester.tap(find.text('Địa chỉ vòng đeo và mật khẩu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wearableUrl')), findsOneWidget);
    expect(find.byKey(const Key('wearablePassword')), findsOneWidget);
  });

  test('Camera BLE: tự nối lại chọn đúng khóa khi ghép 2 camera và xóa khi ngắt tay', () async {
    SharedPreferences.setMockInitialValues({});
    final secure = SecureStore();
    final settings = await AppSettings.load(secure);
    final keyA = '11' * 16;
    final keyB = '22' * 16;
    await settings.pairCamera('CBC-AAAAAA', keyA);
    await settings.pairCamera('CBC-BBBBBB', keyB);

    final tokens = TokenManager(FirebaseAuthClient(), secure);
    final backend1 = FakeBackend();
    final ble1 = FakeCameraBleService();
    final c1 = AppController(
      backend: backend1,
      settings: settings,
      tokens: tokens,
      rtdb: FirebaseRtdbClient(tokens),
      ble: ble1,
      alarm: FakeSound(),
      keepAlive: FakeSound(),
      notifier: FakeNotifier(),
      permissions: FakePermissions(),
      isAndroid: true,
      isIOS: false,
      localMode: true,
      launcher: (_) async => true,
    );
    await c1.start();
    await c1.connectCamera(const CameraScanResult(
      deviceId: 'CBC-BBBBBB',
      remoteId: 'AA:BB:CC:DD:EE:02',
      name: 'CBC-BBBBBB',
      rssi: -55,
    ));
    expect(settings.lastCameraRemoteId, 'AA:BB:CC:DD:EE:02');
    expect(settings.lastCameraDeviceId, 'CBC-BBBBBB');
    c1.dispose();

    // Khởi động lại AppController: phải tự nối lại đúng CBC-BBBBBB với keyB.
    final backend2 = FakeBackend();
    final ble2 = FakeCameraBleService();
    final c2 = AppController(
      backend: backend2,
      settings: settings,
      tokens: tokens,
      rtdb: FirebaseRtdbClient(tokens),
      ble: ble2,
      alarm: FakeSound(),
      keepAlive: FakeSound(),
      notifier: FakeNotifier(),
      permissions: FakePermissions(),
      isAndroid: true,
      isIOS: false,
      localMode: true,
      launcher: (_) async => true,
    );
    await c2.start();
    await Future<void>.delayed(Duration.zero);

    expect(ble2.connectedRemoteIds, ['AA:BB:CC:DD:EE:02']);
    expect(ble2.lastAutoAuthKey, List<int>.filled(16, 0x22));
    expect(c2.connectedCameraId, 'CBC-BBBBBB');

    // Khi BLE báo FALL sau tự nối lại, deviceId phải là CBC-BBBBBB (không rơi về 'camera').
    ble2.alertsCtl.add(const BleAlertMessage(uptimeMs: 100, confidencePercent: 91));
    await Future<void>.delayed(Duration.zero);
    expect(backend2.ingested.single.deviceId, 'CBC-BBBBBB');

    // Ngắt kết nối chủ động phải xóa trạng thái tự nối lại.
    await c2.disconnectCamera();
    expect(settings.lastCameraRemoteId, isNull);
    expect(settings.lastCameraDeviceId, isNull);
    c2.dispose();
  });

  testWidgets('Trang Camera: bấm Bỏ ghép cập nhật ngay giao diện', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late AppController c;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final secure = SecureStore();
      final settings = await AppSettings.load(secure);
      await settings.pairCamera('CBC-123456', 'aa' * 16);
      final tokens = TokenManager(FirebaseAuthClient(), secure);
      c = AppController(
        backend: FakeBackend(),
        settings: settings,
        tokens: tokens,
        rtdb: FirebaseRtdbClient(tokens),
        ble: FakeCameraBleService(),
        alarm: FakeSound(),
        keepAlive: FakeSound(),
        notifier: FakeNotifier(),
        permissions: FakePermissions(),
        isAndroid: true,
        isIOS: false,
        localMode: true,
        launcher: (_) async => true,
      );
      await c.start();
    });
    addTearDown(c.dispose);

    await tester.pumpWidget(wrap(c, const CameraSettingsPage()));
    await tester.pump();
    expect(find.text('CBC-123456'), findsOneWidget);

    await tester.runAsync(() async {
      await c.unpairCamera('CBC-123456');
    });
    await tester.pump();
    expect(find.text('CBC-123456'), findsNothing);
  });
}
