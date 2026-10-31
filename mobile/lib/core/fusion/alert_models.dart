/// Nguồn thiết bị phát cảnh báo.
enum AlertOrigin { wearable, camera }

/// Kênh mà tín hiệu đến điện thoại.
enum AlertChannel {
  udp('UDP'),
  ble('BLE'),
  cloud('Cloud'),
  lan('LAN');

  const AlertChannel(this.label);
  final String label;
}

/// Loại cảnh báo.
enum AlertKind { fall, inactive, resumed }

DateTime _ms(Object? v) => DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

/// Một tín hiệu thô từ một kênh.
class AlertSignal {
  const AlertSignal({
    required this.origin,
    required this.channel,
    required this.kind,
    required this.deviceId,
    required this.receivedAt,
    this.seq,
    this.metric,
    this.sourceIp,
    this.deviceTime,
  });

  final AlertOrigin origin;
  final AlertChannel channel;
  final AlertKind kind;
  final String deviceId;
  final int? seq;

  /// Ngã (vòng đeo): lực va chạm g; bất động: số phút; camera: độ tin cậy 0..1.
  final double? metric;
  final String? sourceIp;
  final DateTime receivedAt;
  final DateTime? deviceTime;

  Map<String, dynamic> toJson() => {
        'origin': origin.name,
        'channel': channel.name,
        'kind': kind.name,
        'deviceId': deviceId,
        'seq': seq,
        'metric': metric,
        'sourceIp': sourceIp,
        'receivedAt': receivedAt.millisecondsSinceEpoch,
        'deviceTime': deviceTime?.millisecondsSinceEpoch,
      };

  static AlertSignal? fromJson(Map<String, dynamic> j) {
    try {
      return AlertSignal(
        origin: AlertOrigin.values.byName(j['origin'] as String),
        channel: AlertChannel.values.byName(j['channel'] as String),
        kind: AlertKind.values.byName(j['kind'] as String),
        deviceId: j['deviceId'] as String,
        seq: (j['seq'] as num?)?.toInt(),
        metric: (j['metric'] as num?)?.toDouble(),
        sourceIp: j['sourceIp'] as String?,
        receivedAt: _ms(j['receivedAt']),
        deviceTime: j['deviceTime'] == null ? null : _ms(j['deviceTime']),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Một sự cố đã gộp từ nhiều tín hiệu/kênh.
class AlertIncident {
  AlertIncident({
    required this.id,
    required this.kind,
    required this.startedAt,
    required this.firstChannel,
    required this.lastSignalAt,
    Set<AlertOrigin>? origins,
    Map<AlertChannel, Duration>? arrivals,
    Map<AlertOrigin, String>? deviceIds,
    Map<AlertOrigin, int>? udpSeq,
    this.impactG,
    this.cameraConfidence,
    this.stillMinutes,
    this.acknowledged = false,
    this.acknowledgedAt,
    this.cloudLatency,
  })  : origins = origins ?? <AlertOrigin>{},
        arrivals = arrivals ?? <AlertChannel, Duration>{},
        deviceIds = deviceIds ?? <AlertOrigin, String>{},
        udpSeq = udpSeq ?? <AlertOrigin, int>{};

  final String id;
  final AlertKind kind;
  final DateTime startedAt;
  final Set<AlertOrigin> origins;
  AlertChannel firstChannel;

  /// Lần đến đầu tiên của mỗi kênh, tính từ [startedAt].
  final Map<AlertChannel, Duration> arrivals;
  final Map<AlertOrigin, String> deviceIds;

  /// Số thứ tự UDP gần nhất của mỗi nguồn (phân biệt sự kiện mới với bản sao).
  final Map<AlertOrigin, int> udpSeq;
  double? impactG;
  double? cameraConfidence;
  double? stillMinutes;
  DateTime lastSignalAt;
  bool acknowledged;
  DateTime? acknowledgedAt;
  Duration? cloudLatency;

  bool get multiSource => origins.length > 1;

  String get label {
    switch (kind) {
      case AlertKind.fall:
        if (multiSource) return 'ĐA NGUỒN XÁC NHẬN (Vòng đeo + Camera AI)';
        return origins.contains(AlertOrigin.camera)
            ? 'TÉ NGÃ — Camera AI'
            : 'TÉ NGÃ — Vòng đeo';
      case AlertKind.inactive:
        return 'BẤT ĐỘNG KÉO DÀI';
      case AlertKind.resumed:
        return 'ĐÃ CỬ ĐỘNG LẠI';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'origins': origins.map((o) => o.name).toList(),
        'firstChannel': firstChannel.name,
        'arrivals': {
          for (final e in arrivals.entries) e.key.name: e.value.inMilliseconds,
        },
        'deviceIds': {for (final e in deviceIds.entries) e.key.name: e.value},
        'udpSeq': {for (final e in udpSeq.entries) e.key.name: e.value},
        'impactG': impactG,
        'cameraConfidence': cameraConfidence,
        'stillMinutes': stillMinutes,
        'lastSignalAt': lastSignalAt.millisecondsSinceEpoch,
        'acknowledged': acknowledged,
        'acknowledgedAt': acknowledgedAt?.millisecondsSinceEpoch,
        'cloudLatency': cloudLatency?.inMilliseconds,
      };

  static AlertIncident? fromJson(Map<String, dynamic> j) {
    try {
      return AlertIncident(
        id: j['id'] as String,
        kind: AlertKind.values.byName(j['kind'] as String),
        startedAt: _ms(j['startedAt']),
        firstChannel: AlertChannel.values.byName(j['firstChannel'] as String),
        lastSignalAt: _ms(j['lastSignalAt']),
        origins: {
          for (final o in (j['origins'] as List? ?? const []))
            AlertOrigin.values.byName(o as String),
        },
        arrivals: {
          for (final e in ((j['arrivals'] as Map?) ?? const {}).entries)
            AlertChannel.values.byName(e.key as String):
                Duration(milliseconds: (e.value as num).toInt()),
        },
        deviceIds: {
          for (final e in ((j['deviceIds'] as Map?) ?? const {}).entries)
            AlertOrigin.values.byName(e.key as String): e.value as String,
        },
        udpSeq: {
          for (final e in ((j['udpSeq'] as Map?) ?? const {}).entries)
            AlertOrigin.values.byName(e.key as String): (e.value as num).toInt(),
        },
        impactG: (j['impactG'] as num?)?.toDouble(),
        cameraConfidence: (j['cameraConfidence'] as num?)?.toDouble(),
        stillMinutes: (j['stillMinutes'] as num?)?.toDouble(),
        acknowledged: j['acknowledged'] as bool? ?? false,
        acknowledgedAt:
            j['acknowledgedAt'] == null ? null : _ms(j['acknowledgedAt']),
        cloudLatency: j['cloudLatency'] == null
            ? null
            : Duration(milliseconds: (j['cloudLatency'] as num).toInt()),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Hành động engine quyết định cho một tín hiệu.
enum FusionAction { newIncident, duplicate, fused, info }

class FusionResult {
  const FusionResult(this.action, this.incident);

  final FusionAction action;
  final AlertIncident incident;

  bool get shouldRing =>
      action == FusionAction.newIncident && incident.kind != AlertKind.resumed;

  Map<String, dynamic> toJson() =>
      {'action': action.name, 'incident': incident.toJson()};

  static FusionResult? fromJson(Map<String, dynamic> j) {
    try {
      final inc = AlertIncident.fromJson(
          Map<String, dynamic>.from(j['incident'] as Map));
      if (inc == null) return null;
      return FusionResult(FusionAction.values.byName(j['action'] as String), inc);
    } catch (_) {
      return null;
    }
  }
}
