import 'dart:async';

import '../core/fusion/alert_fusion_engine.dart';
import '../core/fusion/alert_models.dart';
import '../core/protocol/udp_packet.dart';
import 'app_settings.dart';
import 'event_log_store.dart';
import 'firebase_auth_client.dart';
import 'firebase_rtdb_client.dart';
import 'lan_udp_listener.dart';
import 'wearable_lan_service.dart';

/// Tình trạng từng kênh nhận cảnh báo.
class ChannelHealth {
  const ChannelHealth({
    this.udp = false,
    this.cloud = false,
    this.lan = false,
    this.ble = false,
  });

  final bool udp;
  final bool cloud;
  final bool lan;
  final bool ble;

  ChannelHealth copyWith({bool? udp, bool? cloud, bool? lan, bool? ble}) => ChannelHealth(
        udp: udp ?? this.udp,
        cloud: cloud ?? this.cloud,
        lan: lan ?? this.lan,
        ble: ble ?? this.ble,
      );

  bool of(AlertChannel c) {
    switch (c) {
      case AlertChannel.udp:
        return udp;
      case AlertChannel.cloud:
        return cloud;
      case AlertChannel.lan:
        return lan;
      case AlertChannel.ble:
        return ble;
    }
  }

  Map<String, dynamic> toJson() => {'udp': udp, 'cloud': cloud, 'lan': lan, 'ble': ble};

  factory ChannelHealth.fromJson(Map<dynamic, dynamic> j) => ChannelHealth(
        udp: j['udp'] == true,
        cloud: j['cloud'] == true,
        lan: j['lan'] == true,
        ble: j['ble'] == true,
      );

  @override
  bool operator ==(Object other) =>
      other is ChannelHealth &&
      other.udp == udp &&
      other.cloud == cloud &&
      other.lan == lan &&
      other.ble == ble;

  @override
  int get hashCode => Object.hash(udp, cloud, lan, ble);
}

/// Phát hiện cạnh (alarm/inactive đổi trạng thái) trên chuỗi trạng thái của một kênh.
class _EdgeDetector {
  _EdgeDetector(this.channel, {required this.requireFreshFirst});

  final AlertChannel channel;

  /// Với cloud: snapshot đầu chỉ kích hoạt nếu updatedAt trong 60 giây gần đây.
  final bool requireFreshFirst;

  bool? _alarm;
  bool? _inactive;

  List<AlertSignal> process(
      WearableStatus s, String deviceId, DateTime now) {
    final out = <AlertSignal>[];
    final alarm = s.alarmActive;
    final first = _alarm == null;
    final bool fresh;
    if (!first) {
      fresh = true;
    } else if (!requireFreshFirst) {
      fresh = true;
    } else {
      final at = s.updatedAt;
      fresh = at != null && now.difference(at).abs() <= const Duration(seconds: 60);
    }

    AlertSignal make(AlertKind kind, {double? metric}) => AlertSignal(
          origin: AlertOrigin.wearable,
          channel: channel,
          kind: kind,
          deviceId: deviceId,
          metric: metric,
          sourceIp: s.ip.isEmpty ? null : s.ip,
          receivedAt: now,
          deviceTime: s.updatedAt,
        );

    if (alarm && (first ? fresh : _alarm == false)) out.add(make(AlertKind.fall));
    final inactive = s.inactive;
    if (first) {
      if (inactive && fresh) out.add(make(AlertKind.inactive, metric: s.stillSec / 60));
    } else if (inactive && _inactive == false) {
      out.add(make(AlertKind.inactive, metric: s.stillSec / 60));
    } else if (!inactive && _inactive == true) {
      out.add(make(AlertKind.resumed, metric: s.stillSec / 60));
    }
    _alarm = alarm;
    _inactive = inactive;
    return out;
  }
}

/// Gom UDP + Cloud (SSE) + LAN (poll) + hợp nhất cảnh báo + lưu nhật ký.
///
/// Không phụ thuộc UI, chạy được trong isolate nền.
class MonitorEngine {
  MonitorEngine({
    required this.settings,
    required this.tokens,
    FirebaseRtdbClient? rtdb,
    LanUdpListener? udp,
    EventLogStore? log,
    AlertFusionEngine? fusion,
    this.lanPollInterval = const Duration(seconds: 2),
    DateTime Function()? clock,
    WearableLanService Function(String baseUrl, String password)? lanFactory,
  })  : _rtdb = rtdb ?? FirebaseRtdbClient(tokens, databaseUrl: settings.firebaseDatabaseUrl),
        _udp = udp ?? LanUdpListener(),
        _log = log ?? EventLogStore(),
        _fusion = fusion ?? AlertFusionEngine(),
        _clock = clock ?? DateTime.now,
        _lanFactory = lanFactory ??
            ((url, pass) => WearableLanService(baseUrl: url, password: pass));

  final AppSettings settings;
  final TokenManager tokens;
  final Duration lanPollInterval;

  final FirebaseRtdbClient _rtdb;
  final LanUdpListener _udp;
  final EventLogStore _log;
  final AlertFusionEngine _fusion;
  final DateTime Function() _clock;
  final WearableLanService Function(String baseUrl, String password) _lanFactory;

  final _results = StreamController<FusionResult>.broadcast();
  final _status = StreamController<WearableStatus>.broadcast();
  final _health = StreamController<ChannelHealth>.broadcast();

  final _cloudEdges = _EdgeDetector(AlertChannel.cloud, requireFreshFirst: true);
  final _lanEdges = _EdgeDetector(AlertChannel.lan, requireFreshFirst: false);

  StreamSubscription<LanAlertPacket>? _udpSub;
  StreamSubscription<bool>? _udpHealthSub;
  StreamSubscription<Map<String, dynamic>>? _cloudSub;
  StreamSubscription<bool>? _cloudHealthSub;
  StreamSubscription<FirebaseSession?>? _tokenSub;
  Timer? _pollTimer;
  bool _polling = false;
  bool _running = false;

  WearableLanService? _lan;
  String _lanKey = '';
  String? _learnedIp;
  String _cloudDeviceId = '';

  ChannelHealth _healthState = const ChannelHealth();
  WearableStatus? _lastStatus;

  Stream<FusionResult> get results => _results.stream;
  Stream<WearableStatus> get wearableStatus => _status.stream;
  Stream<ChannelHealth> get channelHealth => _health.stream;
  ChannelHealth get health => _healthState;
  WearableStatus? get lastStatus => _lastStatus;
  List<AlertIncident> get recent => _fusion.recent;
  bool get running => _running;

  /// Địa chỉ vòng đeo đang dùng: cấu hình tay, nếu trống thì IP học được.
  String get wearableBaseUrl {
    final configured = settings.wearableBaseUrl;
    if (configured.isNotEmpty) return configured;
    final ip = _learnedIp;
    return (ip == null || ip.isEmpty) ? '' : 'http://$ip';
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _fusion.restore(await _log.all());

    _udpSub = _udp.packets.listen(_onPacket);
    _udpHealthSub = _udp.health.listen((v) => _setHealth(_healthState.copyWith(udp: v)));
    await _udp.start();
    _setHealth(_healthState.copyWith(udp: _udp.listening));

    _cloudHealthSub =
        _rtdb.connectionChanges.listen((v) => _setHealth(_healthState.copyWith(cloud: v)));
    _tokenSub = tokens.changes.listen((_) => _restartCloud());
    _restartCloud();

    _pollTimer = Timer.periodic(lanPollInterval, (_) => unawaited(_poll()));
    unawaited(_poll());
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _tokenSub?.cancel();
    await _cloudSub?.cancel();
    await _cloudHealthSub?.cancel();
    await _udpSub?.cancel();
    await _udpHealthSub?.cancel();
    _tokenSub = _cloudSub = _cloudHealthSub = _udpSub = _udpHealthSub = null;
    await _udp.stop();
    _lan?.close();
    _lan = null;
    _lanKey = '';
    _setHealth(const ChannelHealth());
  }

  /// Gọi khi cài đặt đổi (deviceId, địa chỉ vòng đeo, mật khẩu...).
  Future<void> applySettings() async {
    if (!_running) return;
    _restartCloud();
    unawaited(_poll());
  }

  Future<void> dispose() async {
    await stop();
    await _results.close();
    await _status.close();
    await _health.close();
  }

  /// Tín hiệu từ nơi khác (vd. BLE ở isolate UI).
  FusionResult ingest(AlertSignal s) {
    final r = _fusion.ingest(s);
    switch (r.action) {
      case FusionAction.newIncident:
      case FusionAction.info:
        unawaited(_log.add(r.incident));
      case FusionAction.duplicate:
      case FusionAction.fused:
        unawaited(_log.update(r.incident));
    }
    if (!_results.isClosed) _results.add(r);
    return r;
  }

  AlertIncident? acknowledge(String id) {
    final i = _fusion.acknowledge(id);
    if (i != null) unawaited(_log.update(i));
    return i;
  }

  /// Xóa lịch sử sự cố trong bộ nhớ và nhật ký đã lưu.
  Future<void> clearHistory() async {
    _fusion.clear();
    await _log.clear();
  }

  void setBleConnected(bool v) => _setHealth(_healthState.copyWith(ble: v));

  // ---- Nguồn tín hiệu ----

  void _onPacket(LanAlertPacket p) {
    if (!p.fromCamera && p.ip.isNotEmpty) _learnedIp = p.ip;
    ingest(AlertSignal(
      origin: p.fromCamera ? AlertOrigin.camera : AlertOrigin.wearable,
      channel: AlertChannel.udp,
      kind: p.kind,
      deviceId: p.deviceId,
      seq: p.seq,
      metric: p.metric,
      sourceIp: p.ip.isEmpty ? null : p.ip,
      receivedAt: _clock(),
    ));
  }

  void _restartCloud() {
    if (!_running) return;
    final id = settings.deviceId;
    if (_cloudSub != null && _cloudDeviceId == id && tokens.signedIn) return;
    unawaited(_cloudSub?.cancel());
    _cloudSub = null;
    if (!tokens.signedIn) {
      _setHealth(_healthState.copyWith(cloud: false));
      return;
    }
    _cloudDeviceId = id;
    _cloudSub = _rtdb.watchDevice(id).listen(_onCloud);
  }

  void _onCloud(Map<String, dynamic> device) {
    final raw = device['status'];
    if (raw is! Map) return;
    final status = WearableStatus.fromJson(raw, source: 'cloud');
    if (status.ip.isNotEmpty && settings.wearableBaseUrl.isEmpty) _learnedIp ??= status.ip;
    _publishStatus(status);
    for (final s in _cloudEdges.process(status, settings.deviceId, _clock())) {
      ingest(s);
    }
  }

  Future<void> _poll() async {
    if (!_running || _polling) return;
    final base = wearableBaseUrl;
    if (base.isEmpty) {
      _setHealth(_healthState.copyWith(lan: false));
      return;
    }
    _polling = true;
    try {
      final pass = settings.wearablePassword;
      final key = '$base\n$pass';
      if (_lan == null || _lanKey != key) {
        _lan?.close();
        _lan = _lanFactory(base, pass);
        _lanKey = key;
      }
      final status = await _lan!.getStatus();
      if (!_running) return;
      _setHealth(_healthState.copyWith(lan: true));
      _publishStatus(status);
      for (final s in _lanEdges.process(status, settings.deviceId, _clock())) {
        ingest(s);
      }
    } catch (_) {
      _setHealth(_healthState.copyWith(lan: false));
    } finally {
      _polling = false;
    }
  }

  void _publishStatus(WearableStatus s) {
    _lastStatus = s;
    if (!_status.isClosed) _status.add(s);
  }

  void _setHealth(ChannelHealth h) {
    if (h == _healthState) return;
    _healthState = h;
    if (!_health.isClosed) _health.add(h);
  }

  // ---- Chuyển dữ liệu giữa các isolate ----

  static Map<String, dynamic> resultToJson(FusionResult r) => r.toJson();
  static FusionResult? resultFromJson(Map<dynamic, dynamic> j) =>
      FusionResult.fromJson(Map<String, dynamic>.from(j));
  static Map<String, dynamic> statusToJson(WearableStatus s) => s.toJson();
  static WearableStatus statusFromJson(Map<dynamic, dynamic> j) =>
      WearableStatus.fromIsolateJson(j);
  static Map<String, dynamic> healthToJson(ChannelHealth h) => h.toJson();
  static ChannelHealth healthFromJson(Map<dynamic, dynamic> j) => ChannelHealth.fromJson(j);
  static Map<String, dynamic> signalToJson(AlertSignal s) => s.toJson();
  static AlertSignal? signalFromJson(Map<dynamic, dynamic> j) =>
      AlertSignal.fromJson(Map<String, dynamic>.from(j));
}
