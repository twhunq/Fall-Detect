import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../core/models/cloud_settings.dart';
import '../core/protocol/sse_parser.dart';
import 'firebase_auth_client.dart';

/// Lỗi truy cập Realtime Database, [message] là tiếng Việt.
class RtdbException implements Exception {
  const RtdbException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  factory RtdbException.fromStatus(int status) {
    if (status == 401 || status == 403) {
      return RtdbException(status, 'Không có quyền (kiểm tra /access)');
    }
    return RtdbException(status, 'Lỗi máy chủ Firebase (HTTP $status).');
  }

  static const RtdbException network =
      RtdbException(0, 'Không kết nối được tới Firebase.');

  @override
  String toString() => message;
}

/// Truy cập Firebase RTDB qua REST (+ SSE) bằng token từ [TokenManager].
class FirebaseRtdbClient {
  FirebaseRtdbClient(
    this._tokens, {
    http.Client? client,
    String? databaseUrl,
    this.minBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _baseUrl = _trimSlash(databaseUrl ?? AppConfig.firebaseDatabaseUrl);

  final TokenManager _tokens;
  final http.Client _client;
  final String _baseUrl;
  final Duration minBackoff;
  final Duration maxBackoff;

  final StreamController<bool> _connection = StreamController<bool>.broadcast();
  bool _connected = false;

  /// Trạng thái kết nối luồng realtime.
  bool get connected => _connected;
  Stream<bool> get connectionChanges => _connection.stream;

  static String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  void _setConnected(bool v) {
    if (_connected == v) return;
    _connected = v;
    _connection.add(v);
  }

  Future<Uri> _uri(String path, {bool forceRefresh = false}) async {
    final token = await _tokens.idToken(forceRefresh: forceRefresh);
    return Uri.parse('$_baseUrl/$path.json').replace(queryParameters: {'auth': token});
  }

  /// 'owner' | 'viewer' | 'device' | null (không có quyền ghi trong /access).
  Future<String?> fetchRole(String deviceId) async {
    final uid = _tokens.session?.uid;
    if (uid == null) throw FirebaseAuthException.fromCode('NOT_SIGNED_IN');
    final res = await _send('GET', await _uri('access/$deviceId/$uid'));
    final v = jsonDecode(res.body);
    if (v is String && (v == 'owner' || v == 'viewer' || v == 'device')) return v;
    return null;
  }

  Future<void> putSettings(String deviceId, CloudSettings s) async {
    await _send('PUT', await _uri('devices/$deviceId/control/settings'),
        body: jsonEncode(s.toJson()));
  }

  /// Tên người được theo dõi, dùng chung cả nhà (chỉ owner ghi được).
  Future<void> putProfileName(String deviceId, String name) async {
    await _send('PUT', await _uri('devices/$deviceId/profile/name'),
        body: jsonEncode(name));
  }

  Future<void> requestTest(String deviceId) async {
    await _send('PUT', await _uri('devices/$deviceId/control/testAt'),
        body: jsonEncode({'.sv': 'timestamp'}));
  }

  /// Đọc một lần toàn bộ `/devices/<id>`.
  Future<Map<String, dynamic>> fetchDevice(String deviceId) async {
    final res = await _send('GET', await _uri('devices/$deviceId'));
    final v = jsonDecode(res.body);
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  Future<http.Response> _send(String method, Uri uri, {String? body}) async {
    final req = http.Request(method, uri);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = body;
    }
    try {
      final res =
          await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 20)));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw RtdbException.fromStatus(res.statusCode);
      }
      return res;
    } on RtdbException {
      rethrow;
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      throw RtdbException.network;
    }
  }

  /// Theo dõi `/devices/<id>` bằng SSE; mỗi put/patch phát lại toàn bộ map.
  ///
  /// Tự kết nối lại (backoff 1 s → 30 s) và chủ động nối lại bằng token mới
  /// trước khi token hết hạn, hoặc khi gặp auth_revoked/401.
  Stream<Map<String, dynamic>> watchDevice(String deviceId) {
    late final StreamController<Map<String, dynamic>> controller;
    var cancelled = false;
    final stop = Completer<void>();

    Future<void> run() async {
      var backoff = minBackoff;
      var forceRefresh = false;
      while (!cancelled) {
        if (!_tokens.signedIn) break;
        var gotData = false;
        final abort = Completer<void>();
        Timer? expiry;
        try {
          final uri = await _uri('devices/$deviceId', forceRefresh: forceRefresh);
          forceRefresh = false;
          final req = http.AbortableRequest('GET', uri, abortTrigger: abort.future)
            ..headers['Accept'] = 'text/event-stream'
            ..headers['Cache-Control'] = 'no-cache';
          final res = await _client.send(req).timeout(const Duration(seconds: 20));
          if (res.statusCode != 200) {
            if (res.statusCode == 401) forceRefresh = true;
            await res.stream.drain<void>();
            throw RtdbException.fromStatus(res.statusCode);
          }
          final until = _tokens.session!.expiresAt
              .subtract(TokenManager.refreshMargin)
              .difference(DateTime.now());
          expiry = Timer(until < const Duration(seconds: 10) ? const Duration(seconds: 10) : until, () {
            if (!abort.isCompleted) abort.complete();
          });
          stop.future.then((_) {
            if (!abort.isCompleted) abort.complete();
          });
          final tree = JsonTree();
          final parser = SseParser();
          var reconnect = false;
          await for (final chunk in res.stream.transform(utf8.decoder)) {
            for (final ev in parser.add(chunk)) {
              if (ev.event == 'put' || ev.event == 'patch') {
                final msg = jsonDecode(ev.data);
                if (msg is! Map) continue;
                final path = (msg['path'] as String?) ?? '/';
                final data = msg['data'];
                if (ev.event == 'put') {
                  tree.applyPut(path, data);
                } else if (data is Map) {
                  tree.applyPatch(path, data);
                }
                if (!gotData) {
                  gotData = true;
                  backoff = minBackoff;
                  _setConnected(true);
                }
                if (!controller.isClosed) controller.add(_snapshot(tree.root));
              } else if (ev.event == 'auth_revoked' || ev.event == 'cancel') {
                forceRefresh = true;
                reconnect = true;
              }
            }
            if (reconnect || cancelled) break;
          }
        } catch (_) {
          // Mọi lỗi (mạng, quyền, hủy) đều dẫn tới nối lại sau backoff.
        } finally {
          expiry?.cancel();
          if (!abort.isCompleted) abort.complete();
        }
        _setConnected(false);
        if (cancelled) break;
        if (gotData) {
          // Luồng đang chạy bị ngắt: nối lại ngay một lần.
          await Future.any([Future<void>.delayed(minBackoff), stop.future]);
        } else {
          await Future.any([Future<void>.delayed(backoff), stop.future]);
          backoff = backoff * 2 > maxBackoff ? maxBackoff : backoff * 2;
        }
      }
      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () => unawaited(run()),
      onCancel: () {
        cancelled = true;
        if (!stop.isCompleted) stop.complete();
      },
    );
    return controller.stream;
  }

  static Map<String, dynamic> _snapshot(dynamic root) {
    if (root is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(root)) as Map);
  }

  void close() {
    _client.close();
    _connection.close();
  }
}
