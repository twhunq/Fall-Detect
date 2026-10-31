import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config.dart';
import '../core/protocol/udp_packet.dart';

/// Nghe gói cảnh báo UDP quảng bá trong LAN (cổng [AppConfig.udpPort]).
class LanUdpListener {
  LanUdpListener({this.port = AppConfig.udpPort});

  final int port;
  final StreamController<LanAlertPacket> _packets =
      StreamController<LanAlertPacket>.broadcast();
  final StreamController<bool> _health = StreamController<bool>.broadcast();

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  Timer? _retry;
  bool _running = false;
  bool _listening = false;
  Duration _backoff = const Duration(seconds: 1);

  Stream<LanAlertPacket> get packets => _packets.stream;

  /// true khi socket đang mở.
  Stream<bool> get health => _health.stream;
  bool get listening => _listening;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _bind();
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    _retry = null;
    await _close();
  }

  Future<RawDatagramSocket> _open() async {
    try {
      return await RawDatagramSocket.bind(InternetAddress.anyIPv4, port,
          reuseAddress: true, reusePort: true);
    } catch (_) {
      // Android/Windows không hỗ trợ reusePort.
      return RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
    }
  }

  Future<void> _bind() async {
    if (!_running) return;
    try {
      final socket = await _open();
      socket.broadcastEnabled = true;
      _socket = socket;
      _backoff = const Duration(seconds: 1);
      _setListening(true);
      _sub = socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          Datagram? d;
          while ((d = socket.receive()) != null) {
            final text = utf8.decode(d!.data, allowMalformed: true);
            final p = LanAlertPacket.parse(text);
            if (p != null && !_packets.isClosed) _packets.add(p);
          }
        },
        onError: (_) => _scheduleRetry(),
        onDone: _scheduleRetry,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    unawaited(_close());
    if (!_running || _retry != null) return;
    _retry = Timer(_backoff, () {
      _retry = null;
      unawaited(_bind());
    });
    _backoff = _backoff * 2 > const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : _backoff * 2;
  }

  Future<void> _close() async {
    final sub = _sub;
    final socket = _socket;
    _sub = null;
    _socket = null;
    await sub?.cancel();
    socket?.close();
    _setListening(false);
  }

  void _setListening(bool v) {
    if (_listening == v) return;
    _listening = v;
    if (!_health.isClosed) _health.add(v);
  }

  Future<void> dispose() async {
    await stop();
    await _packets.close();
    await _health.close();
  }
}
