import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../core/fusion/alert_models.dart';
import '../services/monitor_engine.dart';
import '../services/wearable_lan_service.dart';
import 'background_service.dart';

/// Nguon giam sat cho UI: engine chay ngay trong isolate nay hoac trong service nen.
abstract class MonitorBackend {
  Future<void> start();
  Future<void> stop();

  Stream<FusionResult> get results;
  Stream<WearableStatus> get status;
  Stream<ChannelHealth> get health;

  /// Phat khi danh sach su co thay doi (ket qua moi, snapshot, xac nhan).
  Stream<void> get recentChanged;

  List<AlertIncident> get recent;
  ChannelHealth get currentHealth;
  WearableStatus? get lastStatus;

  /// Dia chi vong deo dang dung (cau hinh tay hoac hoc tu UDP/Cloud); rong neu chua biet.
  String get wearableBaseUrl;

  /// True neu backend tu hien thong bao khi app o nen (service Android).
  bool get notifiesInBackground;

  void ingest(AlertSignal s);
  Future<void> acknowledge(String id);

  /// Xoa lich su su co (bo nho engine + nhat ky).
  Future<void> clearHistory();

  /// Cai dat/phien dang nhap vua doi: nap lai va ap dung.
  Future<void> reload();

  /// Yeu cau trang thai moi nhat (chi co nghia voi service nen).
  Future<void> sync();

  void setBleConnected(bool v);
}

/// Engine chay trong isolate UI (iOS luon dung; Android khi tat service nen).
class LocalMonitorBackend implements MonitorBackend {
  LocalMonitorBackend(this.engine);

  final MonitorEngine engine;
  final _recentChanged = StreamController<void>.broadcast();
  StreamSubscription<FusionResult>? _sub;

  @override
  Future<void> start() async {
    _sub ??= engine.results.listen((_) => _recentChanged.add(null));
    await engine.start();
    _recentChanged.add(null);
  }

  @override
  Future<void> stop() async {
    await engine.stop();
  }

  @override
  Stream<FusionResult> get results => engine.results;
  @override
  Stream<WearableStatus> get status => engine.wearableStatus;
  @override
  Stream<ChannelHealth> get health => engine.channelHealth;
  @override
  Stream<void> get recentChanged => _recentChanged.stream;
  @override
  List<AlertIncident> get recent => engine.recent;
  @override
  ChannelHealth get currentHealth => engine.health;
  @override
  WearableStatus? get lastStatus => engine.lastStatus;
  @override
  String get wearableBaseUrl => engine.wearableBaseUrl;
  @override
  bool get notifiesInBackground => false;

  @override
  void ingest(AlertSignal s) => engine.ingest(s);

  @override
  Future<void> acknowledge(String id) async {
    engine.acknowledge(id);
    _recentChanged.add(null);
  }

  @override
  Future<void> reload() async {
    try {
      await engine.settings.reload();
      await engine.applySettings();
    } catch (e) {
      debugPrint('LocalMonitorBackend.reload loi: $e');
    }
  }

  @override
  Future<void> sync() async {}

  @override
  Future<void> clearHistory() async {
    await engine.clearHistory();
    _recentChanged.add(null);
  }

  @override
  void setBleConnected(bool v) => engine.setBleConnected(v);
}

/// Proxy toi MonitorEngine trong foreground service (Android).
class ServiceMonitorBackend implements MonitorBackend {
  ServiceMonitorBackend({FlutterBackgroundService? service})
      : _service = service ?? FlutterBackgroundService();

  final FlutterBackgroundService _service;

  final _results = StreamController<FusionResult>.broadcast();
  final _status = StreamController<WearableStatus>.broadcast();
  final _health = StreamController<ChannelHealth>.broadcast();
  final _recentChanged = StreamController<void>.broadcast();
  final List<StreamSubscription<Map<String, dynamic>?>> _subs = [];

  List<AlertIncident> _recent = [];
  ChannelHealth _healthState = const ChannelHealth();
  WearableStatus? _lastStatus;
  String _baseUrl = '';

  @override
  Stream<FusionResult> get results => _results.stream;
  @override
  Stream<WearableStatus> get status => _status.stream;
  @override
  Stream<ChannelHealth> get health => _health.stream;
  @override
  Stream<void> get recentChanged => _recentChanged.stream;
  @override
  List<AlertIncident> get recent => List.unmodifiable(_recent);
  @override
  ChannelHealth get currentHealth => _healthState;
  @override
  WearableStatus? get lastStatus => _lastStatus;
  @override
  String get wearableBaseUrl => _baseUrl;
  @override
  bool get notifiesInBackground => true;

  void _listen() {
    if (_subs.isNotEmpty) return;
    _subs.add(_service.on('result').listen((e) {
      if (e == null) return;
      final r = MonitorEngine.resultFromJson(e);
      if (r == null) return;
      _upsert(r.incident);
      _results.add(r);
      _recentChanged.add(null);
    }));
    _subs.add(_service.on('status').listen((e) {
      if (e == null) return;
      _lastStatus = MonitorEngine.statusFromJson(e);
      _status.add(_lastStatus!);
    }));
    _subs.add(_service.on('health').listen((e) {
      if (e == null) return;
      _healthState = MonitorEngine.healthFromJson(e);
      _health.add(_healthState);
    }));
    _subs.add(_service.on('snapshot').listen((e) {
      if (e == null) return;
      final list = <AlertIncident>[];
      for (final m in (e['recent'] as List? ?? const [])) {
        if (m is Map) {
          final i = AlertIncident.fromJson(Map<String, dynamic>.from(m));
          if (i != null) list.add(i);
        }
      }
      _recent = list;
      if (e['status'] is Map) {
        _lastStatus = MonitorEngine.statusFromJson(e['status'] as Map);
        _status.add(_lastStatus!);
      }
      if (e['health'] is Map) {
        _healthState = MonitorEngine.healthFromJson(e['health'] as Map);
        _health.add(_healthState);
      }
      _baseUrl = e['baseUrl'] as String? ?? _baseUrl;
      _recentChanged.add(null);
    }));
  }

  void _upsert(AlertIncident i) {
    final at = _recent.indexWhere((x) => x.id == i.id);
    final list = [..._recent];
    if (at < 0) {
      list.insert(0, i);
    } else {
      list[at] = i;
    }
    _recent = list;
  }

  @override
  Future<void> start() async {
    _listen();
    try {
      if (!await _service.isRunning()) {
        await AppBackgroundService.start();
      }
    } catch (e) {
      debugPrint('ServiceMonitorBackend.start loi: $e');
    }
    await sync();
  }

  @override
  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await AppBackgroundService.stop();
  }

  @override
  Future<void> clearHistory() async {
    _recent = [];
    _service.invoke('clear');
    _recentChanged.add(null);
  }

  @override
  void ingest(AlertSignal s) => _service.invoke('signal', MonitorEngine.signalToJson(s));

  @override
  Future<void> acknowledge(String id) async {
    final at = _recent.indexWhere((x) => x.id == id);
    if (at >= 0) {
      _recent[at]
        ..acknowledged = true
        ..acknowledgedAt = DateTime.now();
    }
    _service.invoke('ack', {'id': id});
    _recentChanged.add(null);
  }

  @override
  Future<void> reload() async => _service.invoke('reload');

  @override
  Future<void> sync() async => _service.invoke('sync');

  @override
  void setBleConnected(bool v) {
    // BLE nam o isolate UI; controller tu gop vao suc khoe hien thi.
  }
}
