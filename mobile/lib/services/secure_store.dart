import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kho lưu bí mật (khóa thiết bị, mật khẩu, token).
///
/// Nếu Keychain/Keystore lỗi (vd. iOS -34018 trên bản ký bằng Sideloadly), tự
/// chuyển hẳn sang SharedPreferences (khóa có tiền tố `secure_fallback.`).
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  static const String fallbackPrefix = 'secure_fallback.';

  final FlutterSecureStorage _storage;
  bool _fallback = false;

  /// True khi đã chuyển sang SharedPreferences.
  bool get usingFallback => _fallback;

  Future<String?> read(String key) async {
    if (!_fallback) {
      try {
        return await _storage.read(key: key);
      } catch (_) {
        _fallback = true;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$fallbackPrefix$key');
  }

  Future<void> write(String key, String value) async {
    if (!_fallback) {
      try {
        await _storage.write(key: key, value: value);
        return;
      } catch (_) {
        _fallback = true;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$fallbackPrefix$key', value);
  }

  Future<void> delete(String key) async {
    if (!_fallback) {
      try {
        await _storage.delete(key: key);
        return;
      } catch (_) {
        _fallback = true;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$fallbackPrefix$key');
  }
}
