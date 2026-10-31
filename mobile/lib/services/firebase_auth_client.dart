import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'secure_store.dart';

/// Phiên đăng nhập Firebase.
class FirebaseSession {
  const FirebaseSession({
    required this.uid,
    required this.email,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String uid;
  final String email;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'idToken': idToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
      };

  static FirebaseSession? fromJson(Map<String, dynamic> j) {
    try {
      return FirebaseSession(
        uid: j['uid'] as String,
        email: j['email'] as String? ?? '',
        idToken: j['idToken'] as String,
        refreshToken: j['refreshToken'] as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch((j['expiresAt'] as num).toInt()),
      );
    } catch (_) {
      return null;
    }
  }

  FirebaseSession copyWith({String? idToken, String? refreshToken, DateTime? expiresAt}) =>
      FirebaseSession(
        uid: uid,
        email: email,
        idToken: idToken ?? this.idToken,
        refreshToken: refreshToken ?? this.refreshToken,
        expiresAt: expiresAt ?? this.expiresAt,
      );
}

/// Lỗi đăng nhập/làm mới token, [message] đã là tiếng Việt.
class FirebaseAuthException implements Exception {
  const FirebaseAuthException(this.code, this.message);
  final String code;
  final String message;

  /// Lỗi do thông tin đăng nhập (khác lỗi mạng): phiên không còn dùng được.
  bool get isCredentialError => code != 'NETWORK' && code != 'TOO_MANY_ATTEMPTS_TRY_LATER' && code != 'UNKNOWN';

  static FirebaseAuthException fromCode(String raw) {
    final code = raw.split(RegExp(r'[\s:]')).first;
    const messages = {
      'EMAIL_NOT_FOUND': 'Email chưa được đăng ký.',
      'INVALID_PASSWORD': 'Sai mật khẩu.',
      'INVALID_LOGIN_CREDENTIALS': 'Sai email hoặc mật khẩu.',
      'INVALID_EMAIL': 'Email không hợp lệ.',
      'USER_DISABLED': 'Tài khoản đã bị vô hiệu hóa.',
      'USER_NOT_FOUND': 'Tài khoản không còn tồn tại.',
      'TOO_MANY_ATTEMPTS_TRY_LATER': 'Thử quá nhiều lần, vui lòng đợi một lúc rồi thử lại.',
      'TOKEN_EXPIRED': 'Phiên đăng nhập đã hết hạn, hãy đăng nhập lại.',
      'INVALID_REFRESH_TOKEN': 'Phiên đăng nhập không hợp lệ, hãy đăng nhập lại.',
      'NOT_SIGNED_IN': 'Chưa đăng nhập.',
    };
    return FirebaseAuthException(code, messages[code] ?? 'Đăng nhập thất bại ($code).');
  }

  static const FirebaseAuthException network =
      FirebaseAuthException('NETWORK', 'Không kết nối được mạng, kiểm tra Internet.');

  @override
  String toString() => message;
}

/// Gọi REST Identity Toolkit / Secure Token.
class FirebaseAuthClient {
  FirebaseAuthClient({http.Client? client, String? apiKey})
      : _client = client ?? http.Client(),
        apiKey = apiKey ?? AppConfig.firebaseApiKey;

  final http.Client _client;
  final String apiKey;

  Future<FirebaseSession> signInWithPassword(String email, String password) async {
    final uri = Uri.https('identitytoolkit.googleapis.com',
        '/v1/accounts:signInWithPassword', {'key': apiKey});
    final j = await _post(
      uri,
      jsonEncode({'email': email.trim(), 'password': password, 'returnSecureToken': true}),
      {'Content-Type': 'application/json'},
    );
    return FirebaseSession(
      uid: j['localId'] as String,
      email: j['email'] as String? ?? email.trim(),
      idToken: j['idToken'] as String,
      refreshToken: j['refreshToken'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: _seconds(j['expiresIn']))),
    );
  }

  Future<FirebaseSession> refresh(FirebaseSession old) async {
    final uri = Uri.https('securetoken.googleapis.com', '/v1/token', {'key': apiKey});
    final j = await _post(
      uri,
      'grant_type=refresh_token&refresh_token=${Uri.encodeQueryComponent(old.refreshToken)}',
      {'Content-Type': 'application/x-www-form-urlencoded'},
    );
    return old.copyWith(
      idToken: j['id_token'] as String,
      refreshToken: j['refresh_token'] as String? ?? old.refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: _seconds(j['expires_in']))),
    );
  }

  int _seconds(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 3600;

  Future<Map<String, dynamic>> _post(
      Uri uri, String body, Map<String, String> headers) async {
    final http.Response res;
    try {
      res = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw FirebaseAuthException.network;
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const FirebaseAuthException('UNKNOWN', 'Phản hồi không hợp lệ từ máy chủ Firebase.');
    }
    if (res.statusCode != 200) {
      final err = json['error'];
      final msg = err is Map ? err['message'] : err;
      throw FirebaseAuthException.fromCode('${msg ?? 'UNKNOWN'}');
    }
    return json;
  }

  void close() => _client.close();
}

/// Giữ phiên đăng nhập, tự làm mới token và lưu vào [SecureStore].
class TokenManager {
  TokenManager(this._auth, this._store, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const String storeKey = 'firebase_session';
  static const Duration refreshMargin = Duration(minutes: 5);

  final FirebaseAuthClient _auth;
  final SecureStore _store;
  final DateTime Function() _clock;
  final StreamController<FirebaseSession?> _changes =
      StreamController<FirebaseSession?>.broadcast();

  FirebaseSession? _session;
  Future<FirebaseSession>? _refreshing;

  FirebaseSession? get session => _session;
  bool get signedIn => _session != null;
  Stream<FirebaseSession?> get changes => _changes.stream;

  /// Nạp phiên đã lưu (nếu có).
  Future<FirebaseSession?> restore() async {
    final raw = await _store.read(storeKey);
    if (raw == null) {
      if (_session != null) {
        _session = null;
        _changes.add(null);
      }
      return null;
    }
    try {
      _session = FirebaseSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      _session = null;
    }
    _changes.add(_session);
    return _session;
  }

  Future<FirebaseSession> signIn(String email, String password) async {
    final s = await _auth.signInWithPassword(email, password);
    await _set(s);
    return s;
  }

  Future<void> signOut() async {
    await _store.delete(storeKey);
    _session = null;
    _changes.add(null);
  }

  /// Token hợp lệ; làm mới nếu còn dưới 5 phút. Ném [FirebaseAuthException].
  Future<String> idToken({bool forceRefresh = false}) async {
    final s = _session;
    if (s == null) throw FirebaseAuthException.fromCode('NOT_SIGNED_IN');
    if (!forceRefresh && s.expiresAt.difference(_clock()) > refreshMargin) {
      return s.idToken;
    }
    final fresh = await (_refreshing ??= _refresh(s).whenComplete(() => _refreshing = null));
    return fresh.idToken;
  }

  Future<FirebaseSession> _refresh(FirebaseSession s) async {
    try {
      final fresh = await _auth.refresh(s);
      await _set(fresh);
      return fresh;
    } on FirebaseAuthException catch (e) {
      if (e.isCredentialError) await signOut();
      rethrow;
    }
  }

  Future<void> _set(FirebaseSession s) async {
    _session = s;
    await _store.write(storeKey, jsonEncode(s.toJson()));
    _changes.add(s);
  }

  Future<void> dispose() => _changes.close();
}
