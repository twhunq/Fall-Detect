import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'secure_store.dart';

/// Cài đặt ứng dụng (SharedPreferences; bí mật nằm trong [SecureStore]).
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs, this._secure);

  static const _kDeviceId = 'settings.deviceId';
  static const _kHomeId = 'settings.homeId';
  static const _kBaseUrl = 'settings.wearableBaseUrl';
  static const _kSosPhone = 'settings.sosPhone';
  static const _kSosName = 'settings.sosName';
  static const _kLastCamera = 'settings.lastCameraRemoteId';
  static const _kLastCameraDeviceId = 'settings.lastCameraDeviceId';
  static const _kBackground = 'settings.useBackgroundService';
  static const _kIosKeepAlive = 'settings.iosKeepAlive';
  static const _kFbApiKey = 'settings.firebaseApiKey';
  static const _kFbDbUrl = 'settings.firebaseDatabaseUrl';
  static const _kWearablePassword = 'wearable_password';
  static const _kPairedCameras = 'paired_cameras';

  final SharedPreferences _prefs;
  final SecureStore _secure;

  String _wearablePassword = '';
  Map<String, String> _pairedCameras = {};

  static Future<AppSettings> load(SecureStore secure) async {
    final s = AppSettings._(await SharedPreferences.getInstance(), secure);
    await s.reload();
    return s;
  }

  /// Đọc lại từ bộ nhớ (dùng khi isolate khác đã đổi cài đặt).
  Future<void> reload() async {
    await _prefs.reload();
    _wearablePassword = await _secure.read(_kWearablePassword) ?? '';
    _pairedCameras = _decodeCameras(await _secure.read(_kPairedCameras));
    notifyListeners();
  }

  static Map<String, String> _decodeCameras(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw);
      if (m is Map) {
        return {
          for (final e in m.entries)
            if (e.value is String) e.key.toString(): e.value as String,
        };
      }
    } catch (_) {}
    return {};
  }

  String get deviceId => _prefs.getString(_kDeviceId) ?? AppConfig.defaultDeviceId;
  String get homeId => _prefs.getString(_kHomeId) ?? '';

  /// Rỗng = chưa cấu hình (engine sẽ thử IP học được từ UDP/Cloud).
  String get wearableBaseUrl => _prefs.getString(_kBaseUrl) ?? '';
  String get wearablePassword => _wearablePassword;
  String get sosPhone => _prefs.getString(_kSosPhone) ?? '';
  String get sosName => _prefs.getString(_kSosName) ?? '';
  String? get lastCameraRemoteId => _prefs.getString(_kLastCamera);
  String? get lastCameraDeviceId => _prefs.getString(_kLastCameraDeviceId);
  bool get useBackgroundService => _prefs.getBool(_kBackground) ?? true;
  bool get iosKeepAlive => _prefs.getBool(_kIosKeepAlive) ?? false;
  String? get firebaseApiKeyOverride => _nonEmpty(_prefs.getString(_kFbApiKey));
  String? get firebaseDatabaseUrlOverride => _nonEmpty(_prefs.getString(_kFbDbUrl));

  String get firebaseApiKey => firebaseApiKeyOverride ?? AppConfig.firebaseApiKey;
  String get firebaseDatabaseUrl =>
      firebaseDatabaseUrlOverride ?? AppConfig.firebaseDatabaseUrl;

  /// deviceId camera -> khóa thiết bị (HEX).
  Map<String, String> get pairedCameras => Map.unmodifiable(_pairedCameras);

  static String? _nonEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<void> _setString(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, value);
    }
    notifyListeners();
  }

  Future<void> setDeviceId(String v) => _setString(_kDeviceId, v.trim());
  Future<void> setHomeId(String v) => _setString(_kHomeId, v.trim());
  Future<void> setWearableBaseUrl(String v) => _setString(_kBaseUrl, normalizeBaseUrl(v));
  Future<void> setSosPhone(String v) => _setString(_kSosPhone, v.trim());
  Future<void> setSosName(String v) => _setString(_kSosName, v.trim());
  Future<void> setLastCameraRemoteId(String? v) => _setString(_kLastCamera, v);
  Future<void> setLastCameraDeviceId(String? v) => _setString(_kLastCameraDeviceId, v);
  Future<void> setFirebaseApiKeyOverride(String? v) => _setString(_kFbApiKey, v?.trim());
  Future<void> setFirebaseDatabaseUrlOverride(String? v) => _setString(_kFbDbUrl, v?.trim());

  Future<void> setUseBackgroundService(bool v) async {
    await _prefs.setBool(_kBackground, v);
    notifyListeners();
  }

  Future<void> setIosKeepAlive(bool v) async {
    await _prefs.setBool(_kIosKeepAlive, v);
    notifyListeners();
  }

  Future<void> setWearablePassword(String v) async {
    _wearablePassword = v;
    if (v.isEmpty) {
      await _secure.delete(_kWearablePassword);
    } else {
      await _secure.write(_kWearablePassword, v);
    }
    notifyListeners();
  }

  Future<void> pairCamera(String deviceId, String keyHex) async {
    _pairedCameras = {..._pairedCameras, deviceId: keyHex.toLowerCase()};
    await _secure.write(_kPairedCameras, jsonEncode(_pairedCameras));
    notifyListeners();
  }

  Future<void> unpairCamera(String deviceId) async {
    _pairedCameras = {..._pairedCameras}..remove(deviceId);
    await _secure.write(_kPairedCameras, jsonEncode(_pairedCameras));
    if (lastCameraDeviceId == deviceId) {
      await _prefs.remove(_kLastCamera);
      await _prefs.remove(_kLastCameraDeviceId);
    }
    notifyListeners();
  }

  /// Thêm `http://` nếu thiếu và bỏ dấu `/` cuối; chuỗi rỗng giữ nguyên.
  static String normalizeBaseUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return '';
    if (!s.contains('://')) s = 'http://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}
