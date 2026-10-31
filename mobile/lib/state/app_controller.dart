// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../core/fusion/alert_models.dart';
import '../core/models/cloud_settings.dart';
import '../core/presence.dart' as pres;
import '../core/presence.dart' show WearablePresence, kDefaultPersonName;
import '../core/protocol/ble_protocol.dart';
import '../platform/alarm_player.dart';
import '../platform/monitor_backend.dart';
import '../platform/notifications.dart';
import '../platform/permissions.dart';
import '../services/app_settings.dart';
import '../services/camera_ble_service.dart';
import '../services/event_log_store.dart';
import '../services/firebase_auth_client.dart';
import '../services/firebase_rtdb_client.dart';
import '../services/monitor_engine.dart';
import '../services/wearable_lan_service.dart';

/// Cài đặt cảnh báo đã tải kèm khả năng của firmware.
class AlertSettingsState {
  const AlertSettingsState({
    required this.settings,
    this.telegramAvailable = true,
    this.gmailAvailable = true,
    this.fromCloud = false,
  });
  final CloudSettings settings;
  final bool telegramAvailable;
  final bool gmailAvailable;
  final bool fromCloud;
}

/// Trạng thái ứng dụng; mọi phụ thuộc được tiêm qua constructor để test bằng bản giả.
class AppController extends ChangeNotifier {
  AppController({
    required MonitorBackend backend,
    required this.settings,
    required this.tokens,
    required this.rtdb,
    required this.ble,
    required this.alarm,
    required this.keepAlive,
    required this.notifier,
    required this.permissions,
    EventLogStore? log,
    DateTime Function()? clock,
    WearableLanService Function(String baseUrl, String password)? lanFactory,
    Future<bool> Function(Uri uri)? launcher,
    bool? isAndroid,
    bool? isIOS,
    bool localMode = false,
    Future<void> Function(bool value)? persistLocalMode,
    Future<MonitorBackend> Function(bool useService)? backendFactory,
  })  : backend = backend,
        _log = log,
        _clock = clock ?? DateTime.now,
        _lanFactory = lanFactory ??
            ((url, pass) => WearableLanService(baseUrl: url, password: pass)),
        _launcher = launcher ?? ((uri) => launchUrl(uri)),
        isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid),
        isIOS = isIOS ?? (!kIsWeb && Platform.isIOS),
        _localMode = localMode,
        _persistLocalMode = persistLocalMode,
        _backendFactory = backendFactory;

  MonitorBackend backend;
  final AppSettings settings;
  final TokenManager tokens;
  final FirebaseRtdbClient rtdb;
  final CameraBleService ble;
  final AlarmSound alarm;
  final AlarmSound keepAlive;
  final AlertNotifier notifier;
  final PermissionService permissions;
  final EventLogStore? _log;
  final DateTime Function() _clock;
  final WearableLanService Function(String, String) _lanFactory;
  final Future<bool> Function(Uri) _launcher;
  final bool isAndroid;
  final bool isIOS;
  final Future<void> Function(bool)? _persistLocalMode;
  final Future<MonitorBackend> Function(bool)? _backendFactory;
  final List<StreamSubscription<dynamic>> _backendSubs = [];

  /// Sự cố chưa xác nhận cũ hơn khoảng này không tự bật chuông khi đồng bộ.
  static const Duration staleRingWindow = Duration(minutes: 10);

  final List<StreamSubscription<dynamic>> _subs = [];
  bool _disposed = false;
  bool _started = false;

  // ---- Phiên ----
  bool _localMode;
  String? role;
  bool get signedIn => tokens.signedIn;
  String? get email => tokens.session?.email;

  /// Cần hiện màn đăng nhập: chưa đăng nhập và chưa chọn chế độ nội mạng.
  bool get needsLogin => !signedIn && !_localMode;
  bool get isViewer => signedIn && role == 'viewer';
  bool get canEditSettings => !signedIn || role == 'owner';

  // ---- Vòng đeo ----
  WearableStatus? wearable;
  ChannelHealth _health = const ChannelHealth();
  bool _bleConnected = false;
  DateTime? lastStatusAt;

  /// Kênh hiển thị: kênh bộ nhớ đã báo + BLE của isolate UI.
  ChannelHealth get health => _health.copyWith(ble: _bleConnected);

  /// Lần cuối nhận được tin từ vòng đeo (trạng thái cục bộ hoặc cloud).
  DateTime? get wearableLastSeen =>
      pres.latestSeen(lastStatusAt, wearable?.updatedAt);

  WearablePresence get wearablePresence => pres.wearablePresence(
        lastStatusAt: lastStatusAt,
        deviceUpdatedAt: wearable?.updatedAt,
        now: _clock(),
      );

  /// % pin; null nếu chưa có dữ liệu hoặc đang cắm nguồn.
  int? get batteryPercent {
    final w = wearable;
    return w == null ? null : pres.batteryPercent(w.batteryMv);
  }

  bool get onUsbPower => wearable != null && wearable!.batteryMv < 2000;

  /// Tên người được theo dõi: cloud > local > mặc định.
  String get personName {
    if (signedIn) {
      final p = cloudDevice['profile'];
      final n = p is Map ? p['name'] : null;
      if (n is String && n.isNotEmpty) return n;
    }
    final local = settings.personName;
    return local.isNotEmpty ? local : kDefaultPersonName;
  }

  bool get canEditPersonName => canEditSettings;

  // ---- Sự cố ----
  List<AlertIncident> incidents = const [];
  AlertIncident? ringing;
  final Set<String> _handledIds = {};
  bool appInForeground = true;

  // ---- Camera ----
  List<CameraScanResult> scanResults = const [];
  bool scanning = false;
  String? scanError;
  bool cameraConnected = false;
  bool cameraAuthenticated = false;
  DateTime? lastAlive;
  bool? cameraWifi;
  CameraInfo? cameraInfo;
  DateTime? lastCameraAlertAt;
  double? lastCameraAlertPercent;
  String? connectedCameraId;
  String? cameraMessage;
  StreamSubscription<List<CameraScanResult>>? _scanSub;

  // ---- Cloud ----
  Map<String, dynamic> cloudDevice = const {};

  /// Tab cần mở (đặt bởi hành động như cài đặt qua hotspot); HomeShell đọc rồi xóa.
  int? requestedTab;

  /// UI đọc rồi tự đặt lại false để mở trang cài đặt vòng đeo.
  bool requestWearableSetup = false;

  Timer? _presenceTimer;
  WearablePresence? _lastPresence;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    settings.addListener(_notify);
    _attachBackend();
    _subs
      ..add(ble.alerts.listen(_onBleAlert))
      ..add(ble.connected.listen(_onBleConnected))
      ..add(ble.authenticated.listen((v) {
        cameraAuthenticated = v;
        _notify();
      }))
      ..add(ble.status.listen((s) {
        lastAlive = _clock();
        cameraWifi = s.wifiConnected;
        _notify();
      }))
      ..add(ble.info.listen((i) {
        cameraInfo = i;
        _notify();
      }));
    await backend.start();
    _health = backend.currentHealth;
    wearable = backend.lastStatus;
    _refreshIncidents(allowRing: false);
    if (signedIn) {
      unawaited(refreshRole());
      unawaited(refreshCloudDevice());
    }
    _lastPresence = wearablePresence;
    _presenceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final p = wearablePresence;
      if (p != _lastPresence) {
        _lastPresence = p;
        _notify();
      }
    });
    final id = settings.lastCameraRemoteId;
    if (id != null && settings.pairedCameras.isNotEmpty) {
      unawaited(_autoReconnectCamera(id));
    }
    if (isIOS && settings.iosKeepAlive) unawaited(keepAlive.start());
    _notify();
  }

  void _attachBackend() {
    _backendSubs
      ..add(backend.results.listen(_onResult))
      ..add(backend.status.listen((s) {
        wearable = s;
        lastStatusAt = _clock();
        _notify();
      }))
      ..add(backend.health.listen((h) {
        _health = h;
        _notify();
      }))
      ..add(backend.recentChanged.listen((_) => _refreshIncidents()));
  }

  Future<void> _detachBackend() async {
    for (final s in _backendSubs) {
      await s.cancel();
    }
    _backendSubs.clear();
  }

  Future<void> _autoReconnectCamera(String remoteId) async {
    try {
      final devId = settings.lastCameraDeviceId;
      final keyHex = (devId != null ? settings.pairedCameras[devId] : null) ??
          (settings.pairedCameras.length == 1
              ? settings.pairedCameras.values.first
              : null);
      if (keyHex == null) return;
      connectedCameraId = devId ??
          (settings.pairedCameras.length == 1
              ? settings.pairedCameras.keys.first
              : null);
      ble.setAutoAuthKey(_hexToBytes(keyHex));
      _notify();
      await ble.connect(remoteId);
    } catch (e) {
      debugPrint('Tự nối lại camera thất bại: $e');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _presenceTimer?.cancel();
    if (_started) settings.removeListener(_notify);
    for (final s in [..._subs, ..._backendSubs]) {
      s.cancel();
    }
    _scanSub?.cancel();
    super.dispose();
  }

  // ---- Vòng đời ----

  void setForeground(bool fg) {
    appInForeground = fg;
    if (fg) {
      unawaited(backend.sync());
      unawaited(_syncRingingFromRecent());
    }
  }

  /// Gọi khi bấm thông báo / mở bằng full-screen intent: hỏi service rồi bật màn báo động.
  Future<void> handleNotificationOpen() async {
    await backend.sync();
    // Snapshot đến bất đồng bộ qua recentChanged; thử luôn bản hiện có.
    _refreshIncidents();
  }

  Future<void> _syncRingingFromRecent() async => _refreshIncidents();

  // ---- Sự cố ----

  void _refreshIncidents({bool allowRing = true}) {
    final list = [...backend.recent]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    incidents = list;
    final cur = ringing;
    if (cur != null) {
      final upd = list.where((i) => i.id == cur.id);
      if (upd.isNotEmpty) {
        if (upd.first.acknowledged) {
          _stopRinging(cur.id);
        } else {
          ringing = upd.first;
        }
      }
    } else if (allowRing) {
      final now = _clock();
      for (final i in list) {
        if (!i.acknowledged &&
            i.kind != AlertKind.resumed &&
            !_handledIds.contains(i.id) &&
            now.difference(i.startedAt).abs() <= staleRingWindow) {
          _startRinging(i, notify: false);
          break;
        }
      }
    }
    _notify();
  }

  void _onResult(FusionResult r) {
    final inc = r.incident;
    final at = incidents.indexWhere((i) => i.id == inc.id);
    final list = [...incidents];
    if (at < 0) {
      list.insert(0, inc);
    } else {
      list[at] = inc;
    }
    list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    incidents = list;

    if (r.shouldRing && !_handledIds.contains(inc.id)) {
      _startRinging(inc);
      return;
    }
    if (ringing?.id == inc.id) {
      ringing = inc;
    }
    _notify();
  }

  void _startRinging(AlertIncident inc, {bool notify = true}) {
    _handledIds.add(inc.id);
    ringing = inc;
    unawaited(alarm.start());
    if (!appInForeground && !backend.notifiesInBackground) {
      unawaited(notifier.showAlarm(
        id: notificationIdFor(inc.id),
        title: inc.label,
        body: _bodyFor(inc),
        payload: inc.id,
      ));
    }
    if (notify) _notify();
  }

  void _stopRinging(String id) {
    if (ringing?.id == id) ringing = null;
    unawaited(alarm.stop());
    unawaited(notifier.cancel(notificationIdFor(id)));
  }

  String _bodyFor(AlertIncident i) {
    final parts = <String>[];
    if (i.deviceIds.isNotEmpty) parts.add(i.deviceIds.values.join(', '));
    if (i.impactG != null) parts.add('va chạm ${i.impactG!.toStringAsFixed(1)} g');
    if (i.cameraConfidence != null) {
      parts.add('camera ${(i.cameraConfidence! * 100).round()}%');
    }
    parts.add('kênh ${i.firstChannel.label}');
    return parts.join(' · ');
  }

  /// Người dùng xác nhận đã kiểm tra: tắt chuông, hủy thông báo, báo backend.
  Future<void> acknowledge(String id) async {
    _handledIds.add(id);
    _stopRinging(id);
    final at = incidents.indexWhere((i) => i.id == id);
    if (at >= 0) {
      incidents[at]
        ..acknowledged = true
        ..acknowledgedAt ??= _clock();
    }
    _notify();
    await backend.acknowledge(id);
  }

  Future<void> clearLog() async {
    try {
      await backend.clearHistory();
      await _log?.clear();
    } catch (e) {
      debugPrint('Xóa nhật ký lỗi: $e');
    }
    incidents = const [];
    _notify();
  }

  /// Gọi SOS: luôn gọi số cấp cứu 115.
  Future<bool> callSos() async {
    try {
      return await _launcher(Uri(scheme: 'tel', path: AppConfig.emergencyNumber));
    } catch (e) {
      debugPrint('Gọi SOS lỗi: $e');
      return false;
    }
  }

  // ---- Phiên đăng nhập ----

  Future<void> signIn(String email, String password) async {
    await tokens.signIn(email.trim(), password);
    _localMode = false;
    await _persistLocalMode?.call(false);
    await refreshRole();
    unawaited(refreshCloudDevice());
    await backend.reload();
    _notify();
  }

  Future<void> signOut() async {
    await tokens.signOut();
    role = null;
    cloudDevice = const {};
    _localMode = false;
    await _persistLocalMode?.call(false);
    await backend.reload();
    _notify();
  }

  Future<void> enterLocalMode() async {
    _localMode = true;
    await _persistLocalMode?.call(true);
    _notify();
  }

  /// Cài đặt qua hotspot BaoNga-Setup-XXXX: trỏ địa chỉ vòng đeo về 192.168.4.1.
  Future<void> startHotspotSetup() async {
    await settings.setWearableBaseUrl(AppConfig.wearableHotspotUrl);
    await enterLocalMode();
    requestedTab = 2;
    requestWearableSetup = true;
    await backend.reload();
    _notify();
  }

  Future<void> refreshRole() async {
    try {
      role = await rtdb.fetchRole(settings.deviceId);
    } catch (e) {
      debugPrint('fetchRole lỗi: $e');
      role = null;
    }
    _notify();
  }

  // ---- Cài đặt dùng chung ----

  Future<void> saveWearableConnection(String baseUrl, String password) async {
    await settings.setWearableBaseUrl(baseUrl);
    await settings.setWearablePassword(password);
    await backend.reload();
    _notify();
  }

  Future<void> saveIds(String deviceId, String homeId) async {
    await settings.setDeviceId(deviceId.isEmpty ? AppConfig.defaultDeviceId : deviceId);
    await settings.setHomeId(homeId);
    await backend.reload();
    if (signedIn) unawaited(refreshRole());
    _notify();
  }

  /// Lưu tên người được theo dõi (local, và cloud nếu là owner); null nếu thành công.
  Future<String?> savePersonName(String raw) async {
    final name = pres.normalizePersonName(raw);
    if (name == null) return 'Tên không được để trống.';
    if (signedIn && !canEditSettings) return 'Bạn chỉ có quyền xem.';
    await settings.setPersonName(name);
    if (signedIn) {
      try {
        await rtdb.putProfileName(settings.deviceId, name);
        final profile = cloudDevice['profile'];
        cloudDevice = {
          ...cloudDevice,
          'profile': {
            if (profile is Map) ...Map<String, dynamic>.from(profile),
            'name': name,
          },
        };
      } catch (e) {
        debugPrint('putProfileName lỗi: $e');
        return 'Không lưu được tên lên đám mây. Kiểm tra kết nối mạng rồi thử lại.';
      }
    }
    _notify();
    return null;
  }

  Future<void> setUseBackgroundService(bool v) async {
    await settings.setUseBackgroundService(v);
    final factory = _backendFactory;
    if (factory != null && isAndroid && backend.notifiesInBackground != v) {
      // Chuyển backend ngay: dừng cái cũ (nhả cổng UDP) rồi dựng cái mới.
      await _detachBackend();
      final wasService = backend.notifiesInBackground;
      await backend.stop();
      if (wasService) await Future<void>.delayed(const Duration(seconds: 1));
      backend = await factory(v);
      _attachBackend();
      await backend.start();
      _health = backend.currentHealth;
      wearable = backend.lastStatus;
      _refreshIncidents(allowRing: false);
    }
    _notify();
  }

  Future<void> setIosKeepAlive(bool v) async {
    await settings.setIosKeepAlive(v);
    if (v) {
      await keepAlive.start();
    } else {
      await keepAlive.stop();
    }
    _notify();
  }

  Future<String> requestAllPermissions() async {
    final ble = await permissions.requestBle();
    final cam = await permissions.requestCamera();
    final notif = await permissions.requestNotifications();
    final battery =
        isAndroid ? await permissions.requestIgnoreBatteryOptimizations() : true;
    String f(String n, bool v) => '$n: ${v ? 'đã cấp' : 'chưa cấp'}';
    return [
      f('Bluetooth', ble),
      f('Camera', cam),
      f('Thông báo', notif),
      if (isAndroid) f('Bỏ tối ưu pin', battery),
    ].join(' · ');
  }

  Future<bool> requestBatteryOptimization() =>
      permissions.requestIgnoreBatteryOptimizations();

  // ---- LAN / Cloud ----

  /// Địa chỉ vòng đeo hiện dùng (cấu hình tay, hoặc IP học được).
  String get wearableBaseUrl {
    final s = settings.wearableBaseUrl;
    return s.isNotEmpty ? s : backend.wearableBaseUrl;
  }

  /// Dịch vụ LAN mới (gọi `close()` sau khi dùng); null nếu chưa biết địa chỉ.
  WearableLanService? newLanService() {
    final base = wearableBaseUrl;
    if (base.isEmpty) return null;
    return _lanFactory(base, settings.wearablePassword);
  }

  Future<void> refreshCloudDevice() async {
    if (!signedIn) return;
    try {
      cloudDevice = await rtdb.fetchDevice(settings.deviceId);
      _notify();
    } catch (e) {
      debugPrint('fetchDevice lỗi: $e');
    }
  }

  Map<String, dynamic> get cloudApplied {
    final a = cloudDevice['applied'];
    return a is Map ? Map<String, dynamic>.from(a) : const {};
  }

  /// Tải cài đặt cảnh báo: cloud khi đã đăng nhập, ngược lại qua LAN. Ném [Exception] có thông báo.
  Future<AlertSettingsState> loadAlertSettings() async {
    if (signedIn) {
      final dev = await rtdb.fetchDevice(settings.deviceId);
      cloudDevice = dev;
      _notify();
      final control = dev['control'];
      final raw = control is Map ? control['settings'] : null;
      return AlertSettingsState(
        settings: raw is Map ? CloudSettings.fromJson(raw) : const CloudSettings(),
        fromCloud: true,
      );
    }
    final lan = newLanService();
    if (lan == null) {
      throw const LanException(0, 'Chưa biết địa chỉ vòng đeo. Nhập ở tab "Vòng đeo".');
    }
    try {
      final w = await lan.getSettings();
      return AlertSettingsState(
        settings: w.settings,
        telegramAvailable: w.telegramAvailable,
        gmailAvailable: w.gmailAvailable,
      );
    } finally {
      lan.close();
    }
  }

  /// Lưu cài đặt; trả về null nếu thành công, ngược lại thông báo lỗi.
  Future<String?> saveAlertSettings(CloudSettings s) async {
    if (!canEditSettings) return 'Bạn chỉ có quyền xem.';
    try {
      if (signedIn) {
        await rtdb.putSettings(settings.deviceId, s);
        return null;
      }
      final lan = newLanService();
      if (lan == null) return 'Chưa biết địa chỉ vòng đeo.';
      try {
        final r = await lan.saveSettings(s);
        return r.ok ? null : r.message;
      } finally {
        lan.close();
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Gửi tin thử; trả về thông báo kết quả (hoặc lỗi).
  Future<String> sendTest() async {
    try {
      if (signedIn) {
        await rtdb.requestTest(settings.deviceId);
        // Thiết bị phản hồi qua applied.testMsg; thử vài lần.
        for (var i = 0; i < 6; i++) {
          await Future<void>.delayed(const Duration(seconds: 2));
          await refreshCloudDevice();
          final msg = cloudApplied['testMsg'];
          if (msg is String && msg.isNotEmpty) return msg;
        }
        return 'Đã gửi yêu cầu, chưa nhận phản hồi từ thiết bị.';
      }
      final lan = newLanService();
      if (lan == null) return 'Chưa biết địa chỉ vòng đeo.';
      try {
        return (await lan.sendTest()).message;
      } finally {
        lan.close();
      }
    } catch (e) {
      return e.toString();
    }
  }

  // ---- Camera BLE ----

  void _onBleConnected(bool v) {
    cameraConnected = v;
    _bleConnected = v;
    backend.setBleConnected(v);
    if (!v) {
      cameraAuthenticated = false;
    }
    _notify();
  }

  void _onBleAlert(BleAlertMessage m) {
    lastCameraAlertAt = _clock();
    lastCameraAlertPercent = m.confidencePercent;
    backend.ingest(AlertSignal(
      origin: AlertOrigin.camera,
      channel: AlertChannel.ble,
      kind: AlertKind.fall,
      deviceId: connectedCameraId ?? 'camera',
      metric: m.confidencePercent / 100,
      receivedAt: _clock(),
    ));
    _notify();
  }

  Future<void> startScan() async {
    await _scanSub?.cancel();
    scanning = true;
    scanError = null;
    scanResults = const [];
    _notify();
    final ok = await permissions.requestBle();
    if (!ok) {
      scanning = false;
      scanError = 'Chưa được cấp quyền Bluetooth.';
      _notify();
      return;
    }
    _scanSub = ble.scan().listen(
      (list) {
        scanResults = list;
        _notify();
      },
      onError: (Object e) {
        scanError = 'Quét lỗi: $e';
        scanning = false;
        _notify();
      },
      onDone: () {
        scanning = false;
        _notify();
      },
    );
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await ble.stopScan();
    scanning = false;
    _notify();
  }

  bool isPaired(String deviceId) =>
      deviceId.isNotEmpty && settings.pairedCameras.containsKey(deviceId);

  /// Ghép từ chuỗi cbn://pair?...; trả về null nếu thành công, ngược lại thông báo lỗi.
  Future<String?> pairFromUri(String text) async {
    final code = parsePairingUri(text);
    if (code == null) return 'Mã ghép nối không hợp lệ (cần dạng cbn://pair?id=CBC-XXXXXX&key=...).';
    await settings.pairCamera(code.deviceId, _bytesToHex(code.key));
    cameraMessage = 'Đã ghép ${code.deviceId}.';
    _notify();
    return null;
  }

  Future<String?> connectCamera(CameraScanResult r) async {
    await stopScan();
    cameraMessage = null;
    connectedCameraId = r.deviceId.isEmpty ? r.name : r.deviceId;
    final keyHex = settings.pairedCameras[r.deviceId];
    final key = keyHex == null ? null : _hexToBytes(keyHex);
    ble.setAutoAuthKey(key);
    try {
      await ble.connect(r.remoteId);
      await settings.setLastCameraRemoteId(r.remoteId);
      await settings.setLastCameraDeviceId(r.deviceId.isEmpty ? null : r.deviceId);
      if (key == null) {
        cameraMessage = 'Đã kết nối nhưng chưa ghép (quét QR trên camera).';
      } else if (!ble.isAuthenticated) {
        // Tự xác thực chạy nền sau khi kết nối; xác thực lại để báo kết quả.
        final ok = await ble.authenticate(key);
        cameraMessage = ok ? 'Xác thực OK.' : 'Xác thực thất bại (sai khóa?).';
      }
      _notify();
      return null;
    } catch (e) {
      cameraMessage = 'Kết nối thất bại: $e';
      _notify();
      return cameraMessage;
    }
  }

  Future<void> disconnectCamera() async {
    await ble.disconnect();
    await settings.setLastCameraRemoteId(null);
    await settings.setLastCameraDeviceId(null);
    connectedCameraId = null;
    cameraInfo = null;
    _notify();
  }

  Future<void> unpairCamera(String deviceId) async {
    final wasActive = connectedCameraId == deviceId;
    await settings.unpairCamera(deviceId);
    if (wasActive) {
      ble.setAutoAuthKey(null);
      cameraAuthenticated = false;
    }
    _notify();
  }

  /// Ghi cấu hình; trả về 'OK' hoặc thông báo lỗi.
  Future<String> writeCameraConfig(CameraConfig c) async {
    try {
      buildConfigPayload(c);
    } on ArgumentError catch (e) {
      return '${e.message}';
    }
    if (!ble.isAuthenticated) return 'Cần kết nối và xác thực camera trước.';
    try {
      final r = await ble.writeConfig(c);
      cameraMessage = r;
      _notify();
      return r;
    } catch (e) {
      return 'Ghi cấu hình lỗi: $e';
    }
  }

  static List<int> _hexToBytes(String hex) => [
        for (var i = 0; i + 1 < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];

  static String _bytesToHex(List<int> b) =>
      b.map((x) => (x & 0xFF).toRadixString(16).padLeft(2, '0')).join();
}
