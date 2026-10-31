import '../../config.dart';
import 'alert_models.dart';

/// Gộp tín hiệu từ nhiều kênh/nguồn thành sự cố, chống đổ chuông lặp.
///
/// Thời gian sự kiện lấy từ [AlertSignal.receivedAt] (không dùng đồng hồ máy)
/// để kết quả xác định được trong test.
class AlertFusionEngine {
  AlertFusionEngine({
    this.fusionWindow = AppConfig.fusionWindow,
    this.dedupeWindow = AppConfig.dedupeWindow,
    this.lateCopyWindow = AppConfig.lateCopyWindow,
    DateTime Function()? clock,
    this.maxIncidents = 200,
  }) : _clock = clock ?? DateTime.now;

  final Duration fusionWindow;
  final Duration dedupeWindow;
  final Duration lateCopyWindow;
  final int maxIncidents;
  final DateTime Function() _clock;

  /// Mới nhất ở đầu.
  final List<AlertIncident> _incidents = [];
  final Map<String, Map<AlertOrigin, DateTime>> _lastByOrigin = {};
  final Set<String> _resolved = {};
  int _counter = 0;

  List<AlertIncident> get recent => List.unmodifiable(_incidents);

  FusionResult ingest(AlertSignal s) {
    final dup = _findDuplicate(s);
    if (dup != null) {
      _record(dup, s);
      return FusionResult(FusionAction.duplicate, dup);
    }

    if (s.kind == AlertKind.fall) {
      final target = _findFusionTarget(s);
      if (target != null) {
        _record(target, s);
        return FusionResult(FusionAction.fused, target);
      }
    }

    final incident = _create(s);
    if (s.kind == AlertKind.resumed) {
      _resolveInactive(s.origin, s.receivedAt);
      return FusionResult(FusionAction.info, incident);
    }
    return FusionResult(FusionAction.newIncident, incident);
  }

  AlertIncident? acknowledge(String id) {
    for (final i in _incidents) {
      if (i.id == id) {
        if (!i.acknowledged) {
          i.acknowledged = true;
          i.acknowledgedAt = _clock();
        }
        return i;
      }
    }
    return null;
  }

  /// Nạp lại lịch sử đã lưu (mới nhất trước) để khử trùng sau khi khởi động.
  void restore(List<AlertIncident> saved) {
    for (final i in saved.reversed) {
      _incidents.insert(0, i);
      _lastByOrigin[i.id] = {for (final o in i.origins) o: i.lastSignalAt};
    }
    _trim();
  }

  /// Xóa toàn bộ lịch sử và trạng thái khử trùng.
  void clear() {
    _incidents.clear();
    _lastByOrigin.clear();
    _resolved.clear();
  }

  AlertIncident? _findDuplicate(AlertSignal s) {
    for (final i in _incidents) {
      if (i.kind != s.kind || !i.origins.contains(s.origin)) continue;
      if (i.kind == AlertKind.inactive && _resolved.contains(i.id)) continue;
      final prevSeq = i.udpSeq[s.origin];
      if (s.channel == AlertChannel.udp &&
          s.seq != null &&
          prevSeq != null &&
          prevSeq != s.seq) {
        continue; // Số thứ tự khác: sự kiện mới của firmware.
      }
      if (i.acknowledged) {
        // Đã xác nhận: chỉ bản sao đến muộn (tính từ lúc bắt đầu, không trượt).
        final w = lateCopyWindow < dedupeWindow ? lateCopyWindow : dedupeWindow;
        if (s.receivedAt.difference(i.startedAt).abs() <= w) return i;
        continue;
      }
      final last = _lastByOrigin[i.id]?[s.origin] ?? i.lastSignalAt;
      if (s.receivedAt.difference(last).abs() <= dedupeWindow) return i;
    }
    return null;
  }

  AlertIncident? _findFusionTarget(AlertSignal s) {
    for (final i in _incidents) {
      if (i.kind != AlertKind.fall || i.origins.contains(s.origin)) continue;
      if (s.receivedAt.difference(i.startedAt).abs() <= fusionWindow) return i;
    }
    return null;
  }

  AlertIncident _create(AlertSignal s) {
    final incident = AlertIncident(
      id: '${s.receivedAt.millisecondsSinceEpoch}-${++_counter}',
      kind: s.kind,
      startedAt: s.receivedAt,
      firstChannel: s.channel,
      lastSignalAt: s.receivedAt,
    );
    _incidents.insert(0, incident);
    _record(incident, s);
    _trim();
    return incident;
  }

  void _record(AlertIncident i, AlertSignal s) {
    i.origins.add(s.origin);
    i.deviceIds[s.origin] = s.deviceId;
    var offset = s.receivedAt.difference(i.startedAt);
    if (offset.isNegative) offset = Duration.zero;
    i.arrivals.putIfAbsent(s.channel, () => offset);
    if (s.receivedAt.isAfter(i.lastSignalAt)) i.lastSignalAt = s.receivedAt;
    (_lastByOrigin[i.id] ??= {})[s.origin] = s.receivedAt;
    if (s.channel == AlertChannel.udp && s.seq != null) i.udpSeq[s.origin] = s.seq!;

    final m = s.metric;
    if (m != null) {
      switch (s.kind) {
        case AlertKind.fall:
          if (s.origin == AlertOrigin.camera) {
            i.cameraConfidence ??= m;
          } else {
            i.impactG ??= m;
          }
        case AlertKind.inactive:
        case AlertKind.resumed:
          i.stillMinutes ??= m;
      }
    }
    if (s.channel == AlertChannel.cloud &&
        i.cloudLatency == null &&
        s.deviceTime != null) {
      i.cloudLatency = s.receivedAt.difference(s.deviceTime!);
    }
  }

  void _resolveInactive(AlertOrigin origin, DateTime at) {
    for (final i in _incidents) {
      if (i.kind == AlertKind.inactive &&
          i.origins.contains(origin) &&
          !_resolved.contains(i.id)) {
        _resolved.add(i.id);
        if (!i.acknowledged) {
          i.acknowledged = true;
          i.acknowledgedAt = at;
        }
        return;
      }
    }
  }

  void _trim() {
    while (_incidents.length > maxIncidents) {
      final removed = _incidents.removeLast();
      _lastByOrigin.remove(removed.id);
      _resolved.remove(removed.id);
    }
  }
}
