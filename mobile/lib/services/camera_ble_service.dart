import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../config.dart';
import '../core/protocol/ble_protocol.dart';

/// Một camera tìm thấy khi quét BLE.
class CameraScanResult {
  const CameraScanResult({
    required this.deviceId,
    required this.remoteId,
    required this.name,
    required this.rssi,
    this.advert,
  });

  /// `CBC-XXXXXX` (rỗng nếu không đọc được từ quảng bá hoặc tên).
  final String deviceId;
  final String remoteId;
  final String name;
  final int rssi;
  final CameraAdvert? advert;
}

/// Kết nối BLE tới camera cầu nối. Toàn bộ flutter_blue_plus nằm trong file này.
class CameraBleService {
  CameraBleService();

  final Guid _serviceUuid = Guid(AppConfig.bleServiceUuid);

  final _alerts = StreamController<BleAlertMessage>.broadcast();
  final _status = StreamController<BleStatusMessage>.broadcast();
  final _info = StreamController<CameraInfo>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  final _authenticated = StreamController<bool>.broadcast();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _authChar;
  BluetoothCharacteristic? _configChar;
  final List<StreamSubscription<dynamic>> _charSubs = [];
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  Timer? _reconnectTimer;
  Duration _backoff = const Duration(seconds: 1);

  bool _wantConnected = false;
  bool _isConnected = false;
  bool _isAuthenticated = false;
  bool _connecting = false;
  List<int>? _autoAuthKey;

  Stream<BleAlertMessage> get alerts => _alerts.stream;
  Stream<BleStatusMessage> get status => _status.stream;
  Stream<CameraInfo> get info => _info.stream;
  Stream<bool> get connected => _connected.stream;
  Stream<bool> get authenticated => _authenticated.stream;

  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated;
  String? get remoteId => _device?.remoteId.str;

  /// Nếu đặt, tự xác thực sau mỗi lần (kết nối lại) thành công.
  void setAutoAuthKey(List<int>? key) => _autoAuthKey = key;

  // ---- Quét ----

  /// Quét camera theo service UUID; phát danh sách cập nhật liên tục, kết thúc khi hết [timeout].
  Stream<List<CameraScanResult>> scan({Duration timeout = const Duration(seconds: 8)}) {
    late final StreamController<List<CameraScanResult>> c;
    StreamSubscription<List<ScanResult>>? resultsSub;
    StreamSubscription<bool>? scanningSub;

    Future<void> finish() async {
      await resultsSub?.cancel();
      await scanningSub?.cancel();
      if (!c.isClosed) await c.close();
    }

    c = StreamController<List<CameraScanResult>>(
      onListen: () async {
        try {
          resultsSub = FlutterBluePlus.onScanResults.listen((list) {
            if (!c.isClosed) c.add(list.map(_toResult).toList());
          });
          await FlutterBluePlus.startScan(
            withServices: [_serviceUuid],
            timeout: timeout,
          );
          scanningSub = FlutterBluePlus.isScanning.where((s) => !s).listen((_) => finish());
        } catch (e, st) {
          if (!c.isClosed) c.addError(e, st);
          await finish();
        }
      },
      onCancel: () async {
        await resultsSub?.cancel();
        await scanningSub?.cancel();
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}
      },
    );
    return c.stream;
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  CameraScanResult _toResult(ScanResult r) {
    final advert = parseManufacturerData(r.advertisementData.manufacturerData);
    final name = r.advertisementData.advName.isNotEmpty
        ? r.advertisementData.advName
        : r.device.platformName;
    var id = advert?.deviceId ?? '';
    if (id.isEmpty && name.startsWith('CBC-')) id = name;
    return CameraScanResult(
      deviceId: id,
      remoteId: r.device.remoteId.str,
      name: name,
      rssi: r.rssi,
      advert: advert,
    );
  }

  // ---- Kết nối ----

  /// Kết nối và đăng ký NOTIFY; tự nối lại khi mất kết nối cho tới khi [disconnect].
  Future<void> connect(String remoteId) async {
    _wantConnected = true;
    _reconnectTimer?.cancel();
    if (_device?.remoteId.str != remoteId) {
      await _teardown();
      _device = BluetoothDevice.fromId(remoteId);
    }
    await _stateSub?.cancel();
    _stateSub = _device!.connectionState.listen(_onState);
    await _connectOnce(report: true);
  }

  Future<void> _connectOnce({bool report = false}) async {
    final device = _device;
    if (device == null || _connecting) return;
    _connecting = true;
    try {
      await stopScan();
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
        mtu: 185,
      );
      await _setup(device);
      _backoff = const Duration(seconds: 1);
      _setConnected(true);
      final key = _autoAuthKey;
      if (key != null) unawaited(authenticate(key));
    } catch (e) {
      try {
        await device.disconnect();
      } catch (_) {}
      _setConnected(false);
      _scheduleReconnect();
      if (report) rethrow;
    } finally {
      _connecting = false;
    }
  }

  Future<void> _setup(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final service = services.firstWhere((s) => s.uuid == _serviceUuid);
    BluetoothCharacteristic? find(String uuid) {
      final g = Guid(uuid);
      for (final ch in service.characteristics) {
        if (ch.uuid == g) return ch;
      }
      return null;
    }

    final alert = find(AppConfig.bleAlertUuid);
    final status = find(AppConfig.bleStatusUuid);
    final info = find(AppConfig.bleInfoUuid);
    _authChar = find(AppConfig.bleAuthUuid);
    _configChar = find(AppConfig.bleConfigUuid);

    for (final s in _charSubs) {
      await s.cancel();
    }
    _charSubs.clear();

    void listen<T>(BluetoothCharacteristic? ch, T? Function(String) parse, StreamController<T> out) {
      if (ch == null) return;
      _charSubs.add(ch.onValueReceived.listen((bytes) {
        final msg = parse(utf8.decode(bytes, allowMalformed: true));
        if (msg != null && !out.isClosed) out.add(msg);
      }));
    }

    listen(alert, parseAlert, _alerts);
    listen(status, parseStatus, _status);
    listen(info, parseInfo, _info);
    for (final ch in [alert, status, info]) {
      if (ch != null) await ch.setNotifyValue(true);
    }
    // INFO chỉ NOTIFY khi đổi: đọc một lần để có giá trị hiện tại.
    if (info != null) {
      try {
        final msg = parseInfo(utf8.decode(await info.read(), allowMalformed: true));
        if (msg != null && !_info.isClosed) _info.add(msg);
      } catch (_) {}
    }
  }

  void _onState(BluetoothConnectionState s) {
    if (s == BluetoothConnectionState.disconnected) {
      if (_isConnected) _setConnected(false);
      if (_wantConnected && !_connecting) _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_wantConnected || _reconnectTimer != null) return;
    _reconnectTimer = Timer(_backoff, () {
      _reconnectTimer = null;
      unawaited(_connectOnce().catchError((_) {}));
    });
    _backoff = _backoff * 2 > const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : _backoff * 2;
  }

  void _setConnected(bool v) {
    if (!v && _isAuthenticated) {
      _isAuthenticated = false;
      if (!_authenticated.isClosed) _authenticated.add(false);
    }
    if (_isConnected == v) return;
    _isConnected = v;
    if (!_connected.isClosed) _connected.add(v);
  }

  Future<void> _teardown() async {
    for (final s in _charSubs) {
      await s.cancel();
    }
    _charSubs.clear();
    await _stateSub?.cancel();
    _stateSub = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _authChar = null;
    _configChar = null;
    _setConnected(false);
  }

  /// Ngắt kết nối và không tự nối lại.
  Future<void> disconnect() async {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _teardown();
  }

  // ---- Xác thực và cấu hình ----

  /// Gửi nonce, so khớp HMAC trả về với khóa thiết bị.
  Future<bool> authenticate(List<int> key) async {
    final ch = _authChar;
    if (ch == null || !_isConnected) return false;
    try {
      final nonce = generateNonce();
      await ch.write(utf8.encode(nonce), withoutResponse: false);
      final reply = utf8.decode(await ch.read(), allowMalformed: true).trim();
      final ok = reply.toUpperCase() == computeAuthResponse(key, nonce);
      _isAuthenticated = ok;
      if (!_authenticated.isClosed) _authenticated.add(ok);
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Ghi cấu hình; trả về 'OK' hoặc 'ERR|...'. Cần đã xác thực.
  Future<String> writeConfig(CameraConfig config) async {
    final ch = _configChar;
    if (ch == null || !_isConnected) return 'ERR|CHUA_KET_NOI';
    final payload = buildConfigPayload(config);
    await ch.write(utf8.encode(payload), allowLongWrite: true);
    return utf8.decode(await ch.read(), allowMalformed: true).trim();
  }

  Future<void> dispose() async {
    await disconnect();
    await _alerts.close();
    await _status.close();
    await _info.close();
    await _connected.close();
    await _authenticated.close();
  }
}
