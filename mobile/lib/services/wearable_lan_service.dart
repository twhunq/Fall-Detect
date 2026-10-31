import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models/cloud_settings.dart';

/// Trạng thái vòng đeo (từ /api/status cục bộ hoặc `/devices/<id>/status` trên cloud).
class WearableStatus {
  const WearableStatus({
    this.device = '',
    this.net,
    this.cloud,
    this.activity,
    this.confidence = 0,
    this.alarm = 'off',
    this.imu = false,
    this.model = false,
    this.cal = 'none',
    this.batteryMv = 0,
    this.batteryLow = false,
    this.errors = 0,
    this.rssi = 0,
    this.ip = '',
    this.uptime = 0,
    this.stillSec = 0,
    this.inactive = false,
    this.updatedAt,
    this.source = 'lan',
  });

  final String device;

  /// 'off' | 'wait' | 'ok' (chỉ có ở /api/status).
  final String? net;

  /// 'off' | 'wait' | 'ok' | 'auth' (chỉ có ở /api/status).
  final String? cloud;
  final String? activity;
  final double confidence;

  /// 'off' | 'fall'.
  final String alarm;
  final bool imu;
  final bool model;

  /// 'run' | 'ok' | 'none'.
  final String cal;
  final int batteryMv;
  final bool batteryLow;
  final int errors;
  final int rssi;
  final String ip;
  final int uptime;
  final int stillSec;
  final bool inactive;

  /// Thời điểm thiết bị ghi lên cloud (ms epoch của máy chủ).
  final DateTime? updatedAt;

  /// 'lan' | 'cloud'.
  final String source;

  bool get alarmActive => alarm == 'fall';

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  factory WearableStatus.fromJson(Map<dynamic, dynamic> j, {String source = 'lan'}) {
    final updated = j['updatedAt'];
    return WearableStatus(
      device: j['device'] is String ? j['device'] as String : '',
      net: j['net'] is String ? j['net'] as String : null,
      cloud: j['cloud'] is String ? j['cloud'] as String : null,
      activity: j['activity'] is String ? j['activity'] as String : null,
      confidence: j['confidence'] is num ? (j['confidence'] as num).toDouble() : 0,
      alarm: j['alarm'] is String ? j['alarm'] as String : 'off',
      imu: j['imu'] == true,
      model: j['model'] == true,
      cal: j['cal'] is String ? j['cal'] as String : 'none',
      batteryMv: _int(j['batteryMv']),
      batteryLow: j['batteryLow'] == true,
      errors: _int(j['errors']),
      rssi: _int(j['rssi']),
      ip: j['ip'] is String ? j['ip'] as String : '',
      uptime: _int(j['uptime']),
      stillSec: _int(j['stillSec']),
      inactive: j['inactive'] == true,
      updatedAt: updated is num
          ? DateTime.fromMillisecondsSinceEpoch(updated.toInt())
          : null,
      source: source,
    );
  }

  Map<String, dynamic> toJson() => {
        'device': device,
        'net': net,
        'cloud': cloud,
        'activity': activity,
        'confidence': confidence,
        'alarm': alarm,
        'imu': imu,
        'model': model,
        'cal': cal,
        'batteryMv': batteryMv,
        'batteryLow': batteryLow,
        'errors': errors,
        'rssi': rssi,
        'ip': ip,
        'uptime': uptime,
        'stillSec': stillSec,
        'inactive': inactive,
        'updatedAt': updatedAt?.millisecondsSinceEpoch,
        'source': source,
      };

  static WearableStatus fromIsolateJson(Map<dynamic, dynamic> j) =>
      WearableStatus.fromJson(j, source: j['source'] as String? ?? 'lan');
}

/// Cài đặt đọc từ thiết bị kèm khả năng của firmware.
class WearableSettings {
  const WearableSettings({
    required this.settings,
    required this.telegramAvailable,
    required this.gmailAvailable,
    required this.maxItems,
    required this.maxInactiveMin,
  });

  final CloudSettings settings;
  final bool telegramAvailable;
  final bool gmailAvailable;
  final int maxItems;
  final int maxInactiveMin;
}

/// Kết quả của lệnh POST: `{"ok":..,"msg":..}`.
class LanResult {
  const LanResult({required this.ok, required this.statusCode, required this.message});
  final bool ok;
  final int statusCode;
  final String message;
}

/// Lỗi gọi trang cục bộ của thiết bị.
class LanException implements Exception {
  const LanException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// Gọi API cục bộ của vòng đeo (web_portal.h).
class WearableLanService {
  WearableLanService({
    required String baseUrl,
    String? password,
    http.Client? client,
    this.timeout = const Duration(seconds: 4),
  })  : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _password = password ?? '',
        _client = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final String _password;
  final http.Client _client;

  static const String wrongPassword = 'Sai mật khẩu trang thiết bị';

  Map<String, String> _headers({bool post = false}) => {
        if (_password.isNotEmpty)
          'Authorization': 'Basic ${base64Encode(utf8.encode('admin:$_password'))}',
        if (post) 'X-Requested-With': 'fetch',
      };

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<http.Response> _get(String path) async {
    try {
      return await _client.get(_uri(path), headers: _headers()).timeout(timeout);
    } catch (_) {
      throw const LanException(0, 'Không kết nối được thiết bị trong mạng LAN.');
    }
  }

  Future<http.Response> _post(String path, Map<String, String> form) async {
    try {
      return await _client
          .post(_uri(path), headers: _headers(post: true), body: form)
          .timeout(timeout);
    } catch (_) {
      throw const LanException(0, 'Không kết nối được thiết bị trong mạng LAN.');
    }
  }

  Map<String, dynamic> _jsonOrThrow(http.Response res) {
    if (res.statusCode == 401) throw const LanException(401, wrongPassword);
    if (res.statusCode != 200) {
      throw LanException(res.statusCode, 'Thiết bị trả lỗi HTTP ${res.statusCode}.');
    }
    try {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw LanException(res.statusCode, 'Phản hồi từ thiết bị không hợp lệ.');
    }
  }

  LanResult _result(http.Response res) {
    if (res.statusCode == 401) {
      return const LanResult(ok: false, statusCode: 401, message: wrongPassword);
    }
    var msg = '';
    var ok = res.statusCode == 200;
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is Map) {
        msg = j['msg'] is String ? j['msg'] as String : '';
        if (j['ok'] is bool) ok = (j['ok'] as bool) && res.statusCode == 200;
      }
    } catch (_) {}
    if (msg.isEmpty) msg = ok ? 'Thành công.' : 'Thiết bị trả lỗi HTTP ${res.statusCode}.';
    return LanResult(ok: ok, statusCode: res.statusCode, message: msg);
  }

  Future<LanResult> _postResult(String path, Map<String, String> form) async {
    try {
      return _result(await _post(path, form));
    } on LanException catch (e) {
      return LanResult(ok: false, statusCode: e.statusCode, message: e.message);
    }
  }

  Future<WearableStatus> getStatus() async =>
      WearableStatus.fromJson(_jsonOrThrow(await _get('/api/status')));

  Future<WearableSettings> getSettings() async {
    final j = _jsonOrThrow(await _get('/api/settings'));
    return WearableSettings(
      settings: CloudSettings.fromJson(j),
      telegramAvailable: j['telegramAvailable'] == true,
      gmailAvailable: j['gmailAvailable'] == true,
      maxItems: j['maxItems'] is num ? (j['maxItems'] as num).toInt() : 5,
      maxInactiveMin: j['maxInactiveMin'] is num ? (j['maxInactiveMin'] as num).toInt() : 1440,
    );
  }

  Future<LanResult> saveSettings(CloudSettings s) => _postResult('/api/settings', {
        'telegramOn': s.telegramOn ? '1' : '0',
        'gmailOn': s.gmailOn ? '1' : '0',
        'chatIds': s.chatIds,
        'emailTo': s.emailTo,
        'inactiveMin': '${s.inactiveMin}',
      });

  Future<LanResult> sendTest() => _postResult('/api/test', const {});

  /// JSON thô của /api/wifi (connected, ip, rssi, ap, networks, attempt...).
  Future<Map<String, dynamic>> getWifi() async => _jsonOrThrow(await _get('/api/wifi'));

  Future<LanResult> connectWifi(String ssid, String pass) =>
      _postResult('/api/wifi', {'action': 'connect', 'ssid': ssid, 'pass': pass});

  Future<LanResult> forgetWifi(String ssid) =>
      _postResult('/api/wifi', {'action': 'forget', 'ssid': ssid});

  /// `{"scanning":true}` khi đang quét, hoặc `{"scanning":false,"list":[...]}`.
  Future<Map<String, dynamic>> scanWifi({bool fresh = false}) async =>
      _jsonOrThrow(await _get(fresh ? '/api/wifi/scan?fresh=1' : '/api/wifi/scan'));

  void close() => _client.close();
}
