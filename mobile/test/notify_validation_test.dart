import 'package:bao_nga_iot/core/models/cloud_settings.dart';
import 'package:bao_nga_iot/core/protocol/notify_validation.dart';
import 'package:flutter_test/flutter_test.dart';

SettingsValidation build({
  bool tg = false,
  bool gm = false,
  String chats = '',
  String mails = '',
  int min = 60,
  bool tgAvail = true,
  bool gmAvail = true,
}) =>
    buildSettings(
      telegramOn: tg,
      gmailOn: gm,
      chatIds: chats,
      emailTo: mails,
      inactiveMin: min,
      telegramAvailable: tgAvail,
      gmailAvailable: gmAvail,
    );

void main() {
  test('validChatId', () {
    for (final ok in ['123', '-100123', '@abcde', '@kenh_nho1']) {
      expect(validChatId(ok), isTrue, reason: ok);
    }
    for (final bad in ['', '@abc', '-', 'abc', '12a', '@ab-cd', '1' * 32]) {
      expect(validChatId(bad), isFalse, reason: bad);
    }
    expect(validChatId('1' * 31), isTrue);
  });

  test('validEmail', () {
    for (final ok in ['a@x.vn', 'nguyen.van+tag@mail.example.com']) {
      expect(validEmail(ok), isTrue, reason: ok);
    }
    for (final bad in [
      'a..b@x.vn',
      '.a@x.vn',
      'a.@x.vn',
      '@x.vn',
      'a@x',
      'a@@x.vn',
      'a b@x.vn',
      'a@.x.vn',
      'a@x.vn-',
      'a"b@x.vn',
      'a@x_y.vn',
    ]) {
      expect(validEmail(bad), isFalse, reason: bad);
    }
  });

  test('normalize lists', () {
    final r = normalizeChatIds('123;  -100456\n@kenh12,,');
    expect(r.error, ListError.none);
    expect(r.value, '123, -100456, @kenh12');
    expect(normalizeEmails('a@x.vn b@y.com').value, 'a@x.vn, b@y.com');
    expect(normalizeChatIds('').value, '');
  });

  test('too many items', () {
    final r = build(chats: '1 2 3 4 5 6');
    expect(r.ok, isFalse);
    expect(r.error, 'Tối đa 5 Chat ID.');
    expect(build(mails: 'a@x.vn b@x.vn c@x.vn d@x.vn e@x.vn f@x.vn').error, 'Tối đa 5 Email.');
    expect(build(chats: '1 2 3 4 5').ok, isTrue);
  });

  test('invalid item message', () {
    expect(build(chats: '123 abc').error, 'Chat ID không hợp lệ: "abc"');
    expect(build(mails: 'a@x.vn nope').error, 'Email không hợp lệ: "nope"');
  });

  test('list length caps', () {
    // 5 chat ID 31 ký tự: 5*31 + 4*2 = 163 < 170 nên hợp lệ.
    final chats = List.generate(5, (_) => '1' * 31).join(' ');
    expect(build(chats: chats).ok, isTrue);
    // 5 email 95 ký tự: 5*95 + 8 = 483 < 490 nên hợp lệ.
    String mail(int n) => '${'a' * (n - 5)}@x.vn';
    expect(build(mails: List.generate(5, (_) => mail(95)).join(' ')).ok, isTrue);
  });

  test('inactiveMin', () {
    expect(build(min: 0).ok, isTrue);
    expect(build(min: 1440).ok, isTrue);
    expect(build(min: 1441).error, 'Cảnh báo bất động: tối đa 1440 phút (24 giờ), 0 để tắt.');
  });

  test('parseMinutes', () {
    expect(parseMinutes('90'), 90);
    expect(parseMinutes('0'), 0);
    expect(parseMinutes(''), isNull);
    expect(parseMinutes('-5'), isNull);
    expect(parseMinutes('1.5'), isNull);
    expect(parseMinutes('12a'), isNull);
  });

  test('availability and required recipients', () {
    expect(build(tg: true, chats: '123', tgAvail: false).error,
        'Chưa có TELEGRAM_BOT_TOKEN trong secrets.h, không bật được Telegram.');
    expect(build(gm: true, mails: 'a@x.vn', gmAvail: false).error,
        'Chưa có tài khoản Gmail gửi trong secrets.h, không bật được Gmail.');
    expect(build(tg: true).error, 'Bật Telegram thì cần ít nhất một Chat ID.');
    expect(build(gm: true).error, 'Bật Gmail thì cần ít nhất một email nhận.');
  });

  test('normalized settings + json keys', () {
    final s = build(tg: true, chats: '123;456', min: 30).settings!;
    expect(s.chatIds, '123, 456');
    expect(s.toJson().keys.toSet(),
        {'telegramOn', 'gmailOn', 'chatIds', 'emailTo', 'inactiveMin'});
  });

  test('CloudSettings.fromJson tolerant', () {
    final s = CloudSettings.fromJson({'telegramOn': true, 'chatIds': '1'});
    expect(s.inactiveMin, 60);
    expect(s.telegramOn, isTrue);
    expect(s.gmailOn, isFalse);
    expect(s.emailTo, '');
  });
}
