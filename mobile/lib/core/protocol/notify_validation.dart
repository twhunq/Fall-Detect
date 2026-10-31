import '../models/cloud_settings.dart';

/// Cổng kiểm tra cài đặt thông báo, port nguyên văn từ notify_settings.h.
const int maxItems = 5;
const int chatItemMax = 32;
const int mailItemMax = 96;
const int inactiveMaxMin = 1440;

/// Kích thước bộ đệm firmware (gồm ký tự NUL): độ dài chuỗi phải nhỏ hơn.
const int chatIdsCap = maxItems * (chatItemMax + 2);
const int emailToCap = maxItems * (mailItemMax + 2);

/// Thông báo khi ô số phút không phải số nguyên (web_portal.h).
const String inactiveNotNumberMessage =
    'Cảnh báo bất động: nhập số phút (số nguyên), 0 để tắt.';

enum ListError { none, invalid, tooMany, tooLong }

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isAlnum(int c) =>
    _isDigit(c) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
bool _isSpace(int c) => c == 0x20 || (c >= 0x09 && c <= 0x0D);

/// Chat Telegram: số (nhóm âm) hoặc @kênh_công_khai.
bool validChatId(String s) {
  final n = s.length;
  if (n == 0 || n >= chatItemMax) return false;
  final u = s.codeUnits;
  if (u[0] == 0x40) {
    if (n < 6) return false;
    for (var i = 1; i < n; i++) {
      if (!_isAlnum(u[i]) && u[i] != 0x5F) return false;
    }
    return true;
  }
  var i = u[0] == 0x2D ? 1 : 0;
  if (i >= n) return false;
  for (; i < n; i++) {
    if (!_isDigit(u[i])) return false;
  }
  return true;
}

const String _localSpecials = ".!#\$%&'*+/=?^_`{|}~-";

/// Tập con chặt của RFC 5321: không khoảng trắng, nháy, ký tự điều khiển.
bool validEmail(String s) {
  final n = s.length;
  final at = s.indexOf('@');
  if (n >= mailItemMax || at <= 0 || s.indexOf('@', at + 1) >= 0) return false;
  final u = s.codeUnits;
  for (var i = 0; i < at; i++) {
    if (!_isAlnum(u[i]) && !_localSpecials.codeUnits.contains(u[i])) {
      return false;
    }
  }
  if (s.startsWith('.') || s[at - 1] == '.' || s.contains('..')) return false;
  final domain = s.substring(at + 1);
  final dn = domain.length;
  if (dn < 3 ||
      !domain.contains('.') ||
      domain.startsWith('.') ||
      domain.startsWith('-') ||
      domain.endsWith('.') ||
      domain.endsWith('-')) {
    return false;
  }
  for (final c in domain.codeUnits) {
    if (!_isAlnum(c) && c != 0x2D && c != 0x2E) return false;
  }
  return true;
}

/// Kết quả chuẩn hóa một danh sách.
class ListResult {
  const ListResult(this.error, this.value, this.bad);
  final ListError error;

  /// "a, b, c" khi thành công.
  final String value;

  /// Phần tử gây lỗi (nếu có).
  final String bad;
}

ListResult _normalizeList(
    String input, bool Function(String) valid, int itemCap, int cap) {
  final out = StringBuffer();
  var count = 0;
  final u = input.codeUnits;
  var p = 0;
  var bad = '';
  while (p < u.length) {
    while (p < u.length && (u[p] == 0x2C || u[p] == 0x3B || _isSpace(u[p]))) {
      p++;
    }
    if (p >= u.length) break;
    final start = p;
    while (p < u.length && u[p] != 0x2C && u[p] != 0x3B && !_isSpace(u[p])) {
      p++;
    }
    final n = p - start;
    final keep = n < mailItemMax ? n : mailItemMax;
    final item = String.fromCharCodes(u.sublist(start, start + keep));
    bad = item;
    if (n >= itemCap || !valid(item)) {
      return ListResult(ListError.invalid, '', bad);
    }
    if (++count > maxItems) return ListResult(ListError.tooMany, '', bad);
    if (count > 1) out.write(', ');
    out.write(item);
    if (out.length >= cap) return ListResult(ListError.tooLong, '', bad);
  }
  return ListResult(ListError.none, out.toString(), '');
}

ListResult normalizeChatIds(String input) =>
    _normalizeList(input, validChatId, chatItemMax, chatIdsCap);

ListResult normalizeEmails(String input) =>
    _normalizeList(input, validEmail, mailItemMax, emailToCap);

String describeListError(String what, ListError err, String bad) {
  switch (err) {
    case ListError.tooMany:
      return 'Tối đa $maxItems $what.';
    case ListError.tooLong:
      return 'Danh sách $what quá dài.';
    default:
      final shown = bad.length > 40 ? bad.substring(0, 40) : bad;
      return '$what không hợp lệ: "$shown"';
  }
}

/// Số phút gồm toàn chữ số; null nếu sai.
int? parseMinutes(String s) {
  if (s.isEmpty) return null;
  var n = 0;
  for (final c in s.codeUnits) {
    if (!_isDigit(c) || n > 100000) return null;
    n = n * 10 + (c - 0x30);
  }
  return n;
}

/// Kết quả [buildSettings]: hoặc cài đặt đã chuẩn hóa, hoặc thông báo lỗi.
class SettingsValidation {
  const SettingsValidation.ok(CloudSettings this.settings) : error = null;
  const SettingsValidation.error(String this.error) : settings = null;

  final CloudSettings? settings;
  final String? error;
  bool get ok => settings != null;
}

SettingsValidation buildSettings({
  required bool telegramOn,
  required bool gmailOn,
  required String chatIds,
  required String emailTo,
  required int inactiveMin,
  bool telegramAvailable = true,
  bool gmailAvailable = true,
}) {
  if (inactiveMin < 0 || inactiveMin > inactiveMaxMin) {
    return const SettingsValidation.error(
        'Cảnh báo bất động: tối đa $inactiveMaxMin phút (24 giờ), 0 để tắt.');
  }
  final chats = normalizeChatIds(chatIds);
  if (chats.error != ListError.none) {
    return SettingsValidation.error(
        describeListError('Chat ID', chats.error, chats.bad));
  }
  final mails = normalizeEmails(emailTo);
  if (mails.error != ListError.none) {
    return SettingsValidation.error(
        describeListError('Email', mails.error, mails.bad));
  }
  String? problem;
  if (telegramOn && !telegramAvailable) {
    problem = 'Chưa có TELEGRAM_BOT_TOKEN trong secrets.h, không bật được Telegram.';
  } else if (gmailOn && !gmailAvailable) {
    problem = 'Chưa có tài khoản Gmail gửi trong secrets.h, không bật được Gmail.';
  } else if (telegramOn && chats.value.isEmpty) {
    problem = 'Bật Telegram thì cần ít nhất một Chat ID.';
  } else if (gmailOn && mails.value.isEmpty) {
    problem = 'Bật Gmail thì cần ít nhất một email nhận.';
  }
  if (problem != null) return SettingsValidation.error(problem);
  return SettingsValidation.ok(CloudSettings(
    telegramOn: telegramOn,
    gmailOn: gmailOn,
    chatIds: chats.value,
    emailTo: mails.value,
    inactiveMin: inactiveMin,
  ));
}
