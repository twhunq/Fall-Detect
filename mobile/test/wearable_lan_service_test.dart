import 'dart:convert';

import 'package:bao_nga_iot/core/models/cloud_settings.dart';
import 'package:bao_nga_iot/services/wearable_lan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, [int code = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), code,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  const base = 'http://baonga.local';

  test('getStatus parses fields, no auth header without password', () async {
    late http.BaseRequest seen;
    final svc = WearableLanService(
      baseUrl: '$base/',
      client: MockClient((req) async {
        seen = req;
        return json({
          'device': 'Bao Nga', 'net': 'ok', 'cloud': 'ok', 'activity': null,
          'confidence': 0.5, 'alarm': 'fall', 'imu': true, 'model': true,
          'cal': 'ok', 'batteryMv': 3900, 'batteryLow': false, 'errors': 2,
          'rssi': -60, 'ip': '192.168.1.20', 'uptime': 99, 'stillSec': 120,
          'inactive': true,
        });
      }),
    );
    final s = await svc.getStatus();
    expect(seen.url.toString(), '$base/api/status');
    expect(seen.headers.containsKey('Authorization'), isFalse);
    expect(s.alarmActive, isTrue);
    expect(s.activity, isNull);
    expect(s.batteryMv, 3900);
    expect(s.stillSec, 120);
    expect(s.inactive, isTrue);
    expect(s.source, 'lan');
    expect(s.updatedAt, isNull);
  });

  test('Basic auth on every request', () async {
    final headers = <String?>[];
    final svc = WearableLanService(
      baseUrl: base,
      password: 'secret',
      client: MockClient((req) async {
        headers.add(req.headers['authorization']);
        return json({'ok': true, 'msg': 'x'});
      }),
    );
    await svc.getWifi();
    await svc.sendTest();
    final expected = 'Basic ${base64Encode(utf8.encode('admin:secret'))}';
    expect(headers, [expected, expected]);
  });

  test('POST settings: header, form body, result', () async {
    late http.Request seen;
    final svc = WearableLanService(
      baseUrl: base,
      client: MockClient((req) async {
        seen = req;
        return json({'ok': true, 'msg': 'Đã lưu cài đặt.'});
      }),
    );
    final r = await svc.saveSettings(const CloudSettings(
        telegramOn: true, chatIds: '123, -100', emailTo: 'a@x.vn', inactiveMin: 45));
    expect(seen.method, 'POST');
    expect(seen.url.path, '/api/settings');
    expect(seen.headers['X-Requested-With'] ?? seen.headers['x-requested-with'], 'fetch');
    expect(seen.headers['content-type'], contains('application/x-www-form-urlencoded'));
    expect(Uri.splitQueryString(seen.body), {
      'telegramOn': '1',
      'gmailOn': '0',
      'chatIds': '123, -100',
      'emailTo': 'a@x.vn',
      'inactiveMin': '45',
    });
    expect(r.ok, isTrue);
    expect(r.message, 'Đã lưu cài đặt.');
  });

  test('every POST carries X-Requested-With', () async {
    final seen = <http.Request>[];
    final svc = WearableLanService(
      baseUrl: base,
      client: MockClient((req) async {
        seen.add(req);
        return json({'ok': true, 'msg': ''});
      }),
    );
    await svc.sendTest();
    await svc.connectWifi('Nha', 'matkhau123');
    await svc.forgetWifi('Nha');
    expect(seen.map((r) => r.url.path), ['/api/test', '/api/wifi', '/api/wifi']);
    for (final r in seen) {
      expect(r.method, 'POST');
      expect(r.headers.entries.any((e) => e.key.toLowerCase() == 'x-requested-with' && e.value == 'fetch'),
          isTrue);
    }
    expect(Uri.splitQueryString(seen[1].body), {'action': 'connect', 'ssid': 'Nha', 'pass': 'matkhau123'});
    expect(Uri.splitQueryString(seen[2].body), {'action': 'forget', 'ssid': 'Nha'});
  });

  test('error results: 400 message, 401, network', () async {
    var mode = 0;
    final svc = WearableLanService(
      baseUrl: base,
      client: MockClient((req) async {
        if (mode == 0) return json({'ok': false, 'msg': 'Tối đa 5 Chat ID.'}, 400);
        if (mode == 1) return http.Response('', 401);
        throw Exception('socket');
      }),
    );
    var r = await svc.saveSettings(const CloudSettings());
    expect(r.ok, isFalse);
    expect(r.statusCode, 400);
    expect(r.message, 'Tối đa 5 Chat ID.');
    mode = 1;
    r = await svc.sendTest();
    expect(r.statusCode, 401);
    expect(r.message, 'Sai mật khẩu trang thiết bị');
    await expectLater(svc.getStatus(), throwsA(isA<LanException>()));
    mode = 2;
    r = await svc.sendTest();
    expect(r.ok, isFalse);
    expect(r.statusCode, 0);
  });

  test('getSettings and scanWifi', () async {
    final urls = <String>[];
    final svc = WearableLanService(
      baseUrl: base,
      client: MockClient((req) async {
        urls.add(req.url.toString());
        if (req.url.path == '/api/settings') {
          return json({
            'telegramOn': true, 'gmailOn': false, 'chatIds': '1', 'emailTo': '',
            'telegramAvailable': true, 'gmailAvailable': false, 'maxItems': 5,
            'inactiveMin': 30, 'maxInactiveMin': 1440,
          });
        }
        return json({'scanning': false, 'list': []});
      }),
    );
    final s = await svc.getSettings();
    expect(s.settings.inactiveMin, 30);
    expect(s.telegramAvailable, isTrue);
    expect(s.gmailAvailable, isFalse);
    expect(s.maxInactiveMin, 1440);
    await svc.scanWifi();
    await svc.scanWifi(fresh: true);
    expect(urls.skip(1), ['$base/api/wifi/scan', '$base/api/wifi/scan?fresh=1']);
  });

  test('WearableStatus json round trip', () {
    final s = WearableStatus.fromJson({
      'alarm': 'fall', 'inactive': true, 'updatedAt': 1700000000000, 'ip': '1.2.3.4',
    }, source: 'cloud');
    final back = WearableStatus.fromIsolateJson(s.toJson());
    expect(back.source, 'cloud');
    expect(back.alarmActive, isTrue);
    expect(back.updatedAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
  });
}
