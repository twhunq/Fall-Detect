import 'package:bao_nga_iot/core/fusion/alert_models.dart';
import 'package:bao_nga_iot/core/protocol/udp_packet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parse wearable fall', () {
    final p = LanAlertPacket.parse('BAONGA|1|42|baonga-01|FALL|3.25|192.168.1.20')!;
    expect(p.seq, 42);
    expect(p.deviceId, 'baonga-01');
    expect(p.kind, AlertKind.fall);
    expect(p.metric, 3.25);
    expect(p.ip, '192.168.1.20');
    expect(p.fromCamera, isFalse);
  });

  test('parse camera, trailing CR/LF/NUL', () {
    final p = LanAlertPacket.parse('BAONGA|1|7|CBC-7A3F91|FALL|0.91|192.168.1.30\r\n\u0000')!;
    expect(p.fromCamera, isTrue);
    expect(p.metric, 0.91);
  });

  test('inactive / resumed', () {
    expect(LanAlertPacket.parse('BAONGA|1|1|d|INACTIVE|60|1.1.1.1')!.kind, AlertKind.inactive);
    expect(LanAlertPacket.parse('BAONGA|1|2|d|RESUMED|61|1.1.1.1')!.kind, AlertKind.resumed);
  });

  test('rejects malformed', () {
    for (final bad in [
      'XAONGA|1|1|d|FALL|1|ip',
      'BAONGA|2|1|d|FALL|1|ip',
      'BAONGA|1|1|d|FALL|1',
      'BAONGA|1|1|d|FALL|1|ip|extra',
      'BAONGA|1|x|d|FALL|1|ip',
      'BAONGA|1|-1|d|FALL|1|ip',
      'BAONGA|1|1|d|FALL|abc|ip',
      'BAONGA|1|1|d|BOOM|1|ip',
      'BAONGA|1|1||FALL|1|ip',
      '',
    ]) {
      expect(LanAlertPacket.parse(bad), isNull, reason: bad);
    }
  });
}
