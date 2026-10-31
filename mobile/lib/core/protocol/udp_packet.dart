import '../fusion/alert_models.dart';

/// Gói UDP quảng bá: `BAONGA|1|<seq>|<device_id>|<FALL|INACTIVE|RESUMED>|<metric>|<ip>`.
///
/// metric: vòng đeo FALL = lực va chạm g; INACTIVE/RESUMED = số phút bất động;
/// camera FALL = độ tin cậy 0..1.
class LanAlertPacket {
  const LanAlertPacket({
    required this.version,
    required this.seq,
    required this.deviceId,
    required this.kind,
    required this.metric,
    required this.ip,
  });

  final int version;
  final int seq;
  final String deviceId;
  final AlertKind kind;
  final double metric;
  final String ip;

  bool get fromCamera => deviceId.startsWith('CBC-');

  static LanAlertPacket? parse(String text) {
    var end = text.length;
    while (end > 0) {
      final c = text.codeUnitAt(end - 1);
      if (c == 0x0D || c == 0x0A || c == 0) {
        end--;
      } else {
        break;
      }
    }
    final parts = text.substring(0, end).split('|');
    if (parts.length != 7 || parts[0] != 'BAONGA') return null;
    final version = int.tryParse(parts[1]);
    if (version != 1) return null;
    final seq = int.tryParse(parts[2]);
    if (seq == null || seq < 0) return null;
    final id = parts[3].trim();
    if (id.isEmpty) return null;
    final AlertKind kind;
    switch (parts[4]) {
      case 'FALL':
        kind = AlertKind.fall;
      case 'INACTIVE':
        kind = AlertKind.inactive;
      case 'RESUMED':
        kind = AlertKind.resumed;
      default:
        return null;
    }
    final metric = double.tryParse(parts[5]);
    if (metric == null || !metric.isFinite) return null;
    return LanAlertPacket(
      version: 1,
      seq: seq,
      deviceId: id,
      kind: kind,
      metric: metric,
      ip: parts[6].trim(),
    );
  }
}
