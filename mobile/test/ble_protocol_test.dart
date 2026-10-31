import 'dart:convert';
import 'dart:math';

import 'package:bao_nga_iot/core/protocol/ble_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const master = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
  const mac = [0xa0, 0xb1, 0xc2, 0x7a, 0x3f, 0x91];

  group('auth', () {
    test('computeAuthResponse vector', () {
      final key = List<int>.generate(32, (i) => i);
      expect(computeAuthResponse(key, 'BaoNga-Nonce-0001'), '3B7E7E9C2C996647FF74CA6FAA66860A');
    });

    test('deriveDeviceKeyHex + auth', () {
      final keyHex = deriveDeviceKeyHex(master, mac);
      expect(keyHex, 'cb7083f6dbc680258c3ed3c6f4248ebd761e5658e4235b6df28ffb0e0f253faf');
      final key = List<int>.generate(
          32, (i) => int.parse(keyHex.substring(i * 2, i * 2 + 2), radix: 16));
      expect(computeAuthResponse(key, 'nonce-1234567890abcd'), '55CF0AEFEE0246613AB44C34694FE347');
    });

    test('generateNonce', () {
      final n = generateNonce(random: Random(1));
      expect(n.length, 24);
      expect(RegExp(r'^[A-Za-z0-9]+$').hasMatch(n), isTrue);
      expect(generateNonce(length: 4).length, 16);
      expect(generateNonce(), isNot(generateNonce()));
    });
  });

  group('advert', () {
    test('payload -> device id', () {
      final a = parseManufacturerPayload([2, ...mac])!;
      expect(a.type, 2);
      expect(a.deviceId, 'CBC-7A3F91');
      expect(a.mac, mac);
      expect(parseManufacturerPayload([2, 1, 2, 3]), isNull);
    });

    test('manufacturer map and raw form', () {
      expect(parseManufacturerData({0xFFFF: [2, ...mac]})!.deviceId, 'CBC-7A3F91');
      expect(parseManufacturerData({0x004C: [2, ...mac]}), isNull);
      expect(parseManufacturerData({0: [0xFF, 0xFF, 2, ...mac]})!.deviceId, 'CBC-7A3F91');
    });
  });

  group('pairing uri', () {
    final keyHex = 'ab' * 32;
    test('valid, case-insensitive', () {
      final p = parsePairingUri('cbn://pair?id=cbc-7a3f91&key=${keyHex.toUpperCase()}')!;
      expect(p.deviceId, 'CBC-7A3F91');
      expect(p.key.length, 32);
      expect(p.key.first, 0xab);
    });

    test('invalid', () {
      expect(parsePairingUri('http://pair?id=CBC-7A3F91&key=$keyHex'), isNull);
      expect(parsePairingUri('cbn://pair?id=CBC-7A3F9&key=$keyHex'), isNull);
      expect(parsePairingUri('cbn://pair?id=CBC-7A3F91&key=${'ab' * 31}'), isNull);
      expect(parsePairingUri('cbn://pair?id=CBC-7A3F91&key=${'zz' * 32}'), isNull);
      expect(parsePairingUri('cbn://pair?id=CBC-7A3F91'), isNull);
      expect(parsePairingUri('khong phai uri'), isNull);
    });
  });

  group('config payload', () {
    test('builds fields', () {
      expect(
        buildConfigPayload(const CameraConfig(ssid: 'Nha', password: 'matkhau123', chatId: '-100')),
        'CFG|Nha|matkhau123||-100||',
      );
      expect(buildConfigPayload(const CameraConfig()), 'CFG||||||');
    });

    test('rejects separators', () {
      expect(() => buildConfigPayload(const CameraConfig(ssid: 'a|b')), throwsArgumentError);
      expect(() => buildConfigPayload(const CameraConfig(password: 'a\nb')), throwsArgumentError);
      expect(() => buildConfigPayload(const CameraConfig(token: 'a\rb')), throwsArgumentError);
    });

    test('128 byte limit is in UTF-8 bytes', () {
      expect(() => buildConfigPayload(CameraConfig(token: 'a' * 128)), returnsNormally);
      expect(() => buildConfigPayload(CameraConfig(token: 'a' * 129)), throwsArgumentError);
      // 43 ky tu 3 byte = 129 byte
      expect(utf8.encode('ạ').length, 3);
      expect(() => buildConfigPayload(CameraConfig(ssid: 'ạ' * 43)), throwsArgumentError);
      expect(() => buildConfigPayload(CameraConfig(ssid: 'ạ' * 42)), returnsNormally);
    });
  });

  group('notify parsers', () {
    test('alert', () {
      final a = parseAlert('FALL|87.3|254120')!;
      expect(a.confidencePercent, 87.3);
      expect(a.uptimeMs, 254120);
      expect(parseAlert('ALIVE|1|1'), isNull);
      expect(parseAlert('FALL|x|1'), isNull);
    });

    test('status', () {
      final s = parseStatus('ALIVE|10000|1')!;
      expect(s.uptimeMs, 10000);
      expect(s.wifiConnected, isTrue);
      expect(parseStatus('ALIVE|10000|2'), isNull);
    });

    test('info', () {
      final i = parseInfo('CAM|192.168.1.50|81|/stream|1')!;
      expect(i.alive, isTrue);
      expect(i.streamUri.toString(), 'http://192.168.1.50:81/stream');
      expect(parseInfo('CAM|10.0.0.2|81|stream')!.alive, isNull);
      final unknown = parseInfo('CAM||||0')!;
      expect(unknown.ip, isEmpty);
      expect(unknown.alive, isFalse);
      expect(unknown.streamUri, isNull);
      expect(parseInfo('XXX|a|b|c'), isNull);
    });
  });
}
