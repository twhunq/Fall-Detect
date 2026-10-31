/// Logic thuần Dart: trạng thái hiện diện của vòng đeo, % pin, tên người được theo dõi.
enum WearablePresence { unknown, online, offline }

/// Quá ngưỡng này không nhận tin nào thì coi là mất tín hiệu (khớp web dashboard).
const Duration kWearableOfflineAfter = Duration(seconds: 75);

const String kDefaultPersonName = 'Người thân';

/// Mốc mới hơn trong hai mốc; null nếu cả hai null.
DateTime? latestSeen(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}

WearablePresence wearablePresence({
  DateTime? lastStatusAt,
  DateTime? deviceUpdatedAt,
  required DateTime now,
}) {
  final seen = latestSeen(lastStatusAt, deviceUpdatedAt);
  if (seen == null) return WearablePresence.unknown;
  return now.difference(seen) > kWearableOfflineAfter
      ? WearablePresence.offline
      : WearablePresence.online;
}

// Bảng điện áp (mV) -> % cho LiPo 1 cell, giảm dần theo điện áp.
const List<List<int>> _lipoTable = [
  [4150, 100],
  [4100, 95],
  [4000, 85],
  [3900, 72],
  [3800, 55],
  [3700, 35],
  [3600, 15],
  [3500, 7],
  [3400, 3],
  [3300, 0],
];

/// % pin; null khi mv < 2000 (cắm USB / không có pin).
int? batteryPercent(int mv) {
  if (mv < 2000) return null;
  if (mv >= _lipoTable.first[0]) return 100;
  if (mv <= _lipoTable.last[0]) return 0;
  for (var i = 0; i < _lipoTable.length - 1; i++) {
    final hi = _lipoTable[i], lo = _lipoTable[i + 1];
    if (mv <= hi[0] && mv >= lo[0]) {
      final t = (mv - lo[0]) / (hi[0] - lo[0]);
      return (lo[1] + t * (hi[1] - lo[1])).round().clamp(0, 100);
    }
  }
  return 0;
}

/// Chuẩn hóa tên: trim, gộp khoảng trắng, tối đa 40 ký tự; rỗng -> null.
String? normalizePersonName(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return null;
  final runes = s.runes.toList();
  if (runes.length <= 40) return s;
  return String.fromCharCodes(runes.take(40)).trim();
}
