import 'package:bao_nga_iot/core/presence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 1, 1, 12);

  group('wearablePresence', () {
    test('unknown khi chưa có mốc', () {
      expect(wearablePresence(now: now), WearablePresence.unknown);
    });
    test('biên 75 s', () {
      expect(
          wearablePresence(
              lastStatusAt: now.subtract(const Duration(seconds: 75)), now: now),
          WearablePresence.online);
      expect(
          wearablePresence(
              lastStatusAt: now.subtract(const Duration(seconds: 76)), now: now),
          WearablePresence.offline);
    });
    test('lấy mốc mới hơn và chịu lệch giờ âm', () {
      expect(
          wearablePresence(
              lastStatusAt: now.subtract(const Duration(minutes: 10)),
              deviceUpdatedAt: now.subtract(const Duration(seconds: 5)),
              now: now),
          WearablePresence.online);
      expect(
          wearablePresence(
              deviceUpdatedAt: now.add(const Duration(minutes: 5)), now: now),
          WearablePresence.online);
    });
  });

  test('latestSeen', () {
    final a = DateTime(2026), b = DateTime(2027);
    expect(latestSeen(null, null), isNull);
    expect(latestSeen(a, null), a);
    expect(latestSeen(null, b), b);
    expect(latestSeen(a, b), b);
    expect(latestSeen(b, a), b);
  });

  test('batteryPercent', () {
    expect(batteryPercent(4200), 100);
    expect(batteryPercent(4150), 100);
    expect(batteryPercent(3850), 64); // giữa 72 và 55 -> 63.5 làm tròn
    expect(batteryPercent(3500), 7);
    expect(batteryPercent(3300), 0);
    expect(batteryPercent(3000), 0);
    expect(batteryPercent(1500), isNull);
  });

  group('normalizePersonName', () {
    test('rỗng / khoảng trắng', () {
      expect(normalizePersonName(''), isNull);
      expect(normalizePersonName('   \t '), isNull);
      expect(normalizePersonName('  Bà   Lan  '), 'Bà Lan');
    });
    test('cắt 40 ký tự', () {
      expect(normalizePersonName('a' * 60), 'a' * 40);
    });
    test('tiếng Việt có dấu', () {
      expect(normalizePersonName('Nguyễn Thị Ánh'), 'Nguyễn Thị Ánh');
      expect(normalizePersonName('ệ' * 45)!.runes.length, 40);
    });
  });
}
