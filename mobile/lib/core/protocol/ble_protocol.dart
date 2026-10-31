import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Giao thức BLE của camera cầu nối. Thuần Dart, không phụ thuộc flutter_blue_plus.

const int _manufacturerId = 0xFFFF;
const int _cfgMaxFieldBytes = 128;

String _hex(List<int> bytes, {bool upper = false}) {
  final s = bytes.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0')).join();
  return upper ? s.toUpperCase() : s;
}

List<int>? _fromHex(String s) {
  if (s.length.isOdd) return null;
  final out = <int>[];
  for (var i = 0; i < s.length; i += 2) {
    final v = int.tryParse(s.substring(i, i + 2), radix: 16);
    if (v == null) return null;
    out.add(v);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Quảng bá
// ---------------------------------------------------------------------------

/// Dữ liệu nhà sản xuất trong gói quảng bá: loại máy + MAC.
class CameraAdvert {
  const CameraAdvert({required this.type, required this.mac, required this.deviceId});
  final int type;
  final List<int> mac;
  final String deviceId;
}

/// [payloadAfterCompanyId] = `[type, mac0..mac5]`.
CameraAdvert? parseManufacturerPayload(List<int> payloadAfterCompanyId) {
  if (payloadAfterCompanyId.length < 7) return null;
  final type = payloadAfterCompanyId[0] & 0xFF;
  final mac = payloadAfterCompanyId.sublist(1, 7).map((b) => b & 0xFF).toList();
  final id = 'CBC-${_hex(mac.sublist(3, 6), upper: true)}';
  return CameraAdvert(type: type, mac: mac, deviceId: id);
}

/// Chọn khóa 0xFFFF trong map manufacturerData; chấp nhận cả dạng thô 9 byte
/// bắt đầu bằng FF FF.
CameraAdvert? parseManufacturerData(Map<int, List<int>> data) {
  final payload = data[_manufacturerId];
  if (payload != null) return parseManufacturerPayload(payload);
  for (final v in data.values) {
    if (v.length >= 9 && v[0] == 0xFF && v[1] == 0xFF) {
      return parseManufacturerPayload(v.sublist(2));
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Ghép đôi bằng QR
// ---------------------------------------------------------------------------

class PairingCode {
  const PairingCode({required this.deviceId, required this.key});
  final String deviceId;
  final List<int> key;
}

final RegExp _deviceIdPattern = RegExp(r'^CBC-[0-9A-F]{6}$');

/// `cbn://pair?id=CBC-XXXXXX&key=<64 hex>`.
PairingCode? parsePairingUri(String text) {
  final Uri uri;
  try {
    uri = Uri.parse(text.trim());
  } catch (_) {
    return null;
  }
  if (uri.scheme.toLowerCase() != 'cbn' || uri.host.toLowerCase() != 'pair') {
    return null;
  }
  final id = uri.queryParameters['id']?.trim().toUpperCase();
  final keyHex = uri.queryParameters['key']?.trim();
  if (id == null || keyHex == null || !_deviceIdPattern.hasMatch(id)) {
    return null;
  }
  if (keyHex.length != 64) return null;
  final key = _fromHex(keyHex);
  if (key == null) return null;
  return PairingCode(deviceId: id, key: key);
}

// ---------------------------------------------------------------------------
// Xác thực
// ---------------------------------------------------------------------------

/// 16 byte đầu của HMAC-SHA256(key, nonce) dạng 32 ký tự HEX HOA.
String computeAuthResponse(List<int> deviceKey, String nonce) {
  final mac = Hmac(sha256, deviceKey).convert(utf8.encode(nonce)).bytes;
  return _hex(mac.sublist(0, 16), upper: true);
}

const String _nonceAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// Chuỗi ngẫu nhiên chữ-số ASCII (firmware yêu cầu tối thiểu 8 ký tự).
String generateNonce({int length = 24, Random? random}) {
  final r = random ?? Random.secure();
  final n = length < 16 ? 16 : length;
  return String.fromCharCodes(
      List.generate(n, (_) => _nonceAlphabet.codeUnitAt(r.nextInt(_nonceAlphabet.length))));
}

/// device_key = HMAC-SHA256(master, mac 6 byte), HEX thường.
String deriveDeviceKeyHex(String masterHex, List<int> mac) {
  final master = _fromHex(masterHex.trim());
  if (master == null || master.isEmpty) {
    throw ArgumentError('Khóa gốc không hợp lệ');
  }
  return _hex(Hmac(sha256, master).convert(mac).bytes);
}

// ---------------------------------------------------------------------------
// Cấu hình
// ---------------------------------------------------------------------------

/// Trường để trống/null = giữ nguyên giá trị hiện có trên camera.
class CameraConfig {
  const CameraConfig({
    this.ssid,
    this.password,
    this.token,
    this.chatId,
    this.homeId,
    this.relayUrl,
  });
  final String? ssid;
  final String? password;
  final String? token;
  final String? chatId;
  final String? homeId;
  final String? relayUrl;
}

/// `CFG|<ssid>|<pass>|<token>|<chat_id>|<home>|<relay>`.
String buildConfigPayload(CameraConfig c) {
  final names = ['Tên Wi-Fi', 'Mật khẩu Wi-Fi', 'Token', 'Chat ID', 'Mã nhà', 'Địa chỉ relay'];
  final raw = [c.ssid, c.password, c.token, c.chatId, c.homeId, c.relayUrl];
  final fields = <String>[];
  for (var i = 0; i < raw.length; i++) {
    final v = (raw[i] ?? '').trim();
    if (v.contains('|') || v.contains('\r') || v.contains('\n')) {
      throw ArgumentError('${names[i]} không được chứa ký tự "|" hoặc xuống dòng');
    }
    if (utf8.encode(v).length > _cfgMaxFieldBytes) {
      throw ArgumentError('${names[i]} quá dài (tối đa $_cfgMaxFieldBytes byte)');
    }
    fields.add(v);
  }
  return 'CFG|${fields.join('|')}';
}

// ---------------------------------------------------------------------------
// Bản tin NOTIFY
// ---------------------------------------------------------------------------

class BleAlertMessage {
  const BleAlertMessage({required this.confidencePercent, required this.uptimeMs});
  final double confidencePercent;
  final int uptimeMs;
}

/// `FALL|87.3|254120`.
BleAlertMessage? parseAlert(String text) {
  final p = text.trim().split('|');
  if (p.length < 3 || p[0] != 'FALL') return null;
  final conf = double.tryParse(p[1]);
  final up = int.tryParse(p[2]);
  if (conf == null || up == null || !conf.isFinite) return null;
  return BleAlertMessage(confidencePercent: conf, uptimeMs: up);
}

class BleStatusMessage {
  const BleStatusMessage({required this.uptimeMs, required this.wifiConnected});
  final int uptimeMs;
  final bool wifiConnected;
}

/// `ALIVE|<uptime_ms>|<0/1>`.
BleStatusMessage? parseStatus(String text) {
  final p = text.trim().split('|');
  if (p.length < 3 || p[0] != 'ALIVE') return null;
  final up = int.tryParse(p[1]);
  if (up == null || (p[2] != '0' && p[2] != '1')) return null;
  return BleStatusMessage(uptimeMs: up, wifiConnected: p[2] == '1');
}

class CameraInfo {
  const CameraInfo({required this.ip, required this.port, required this.path, this.alive});
  final String ip;
  final int port;
  final String path;

  /// null nếu bản tin không có trường này.
  final bool? alive;

  /// Địa chỉ xem hình; null khi chưa biết IP.
  Uri? get streamUri {
    if (ip.isEmpty || port <= 0) return null;
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri(scheme: 'http', host: ip, port: port, path: normalized);
  }
}

/// `CAM|<ip>|<port>|<path>[|<alive>]`; `CAM||||0` khi chưa biết.
CameraInfo? parseInfo(String text) {
  final p = text.trim().split('|');
  if (p.length < 4 || p[0] != 'CAM') return null;
  final ip = p[1].trim();
  final port = p[2].trim().isEmpty ? 0 : int.tryParse(p[2].trim());
  if (port == null) return null;
  bool? alive;
  if (p.length >= 5) {
    if (p[4] == '1') alive = true;
    if (p[4] == '0') alive = false;
  }
  return CameraInfo(ip: ip, port: port, path: p[3].trim(), alive: alive);
}
