import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'notifications.dart';

/// Giao dien xin quyen (thay bang ban gia trong test).
abstract class PermissionService {
  Future<bool> requestBle();
  Future<bool> requestCamera();
  Future<bool> requestNotifications();
  Future<bool> requestIgnoreBatteryOptimizations();
  Future<bool> isIgnoringBatteryOptimizations();
}

/// Xin quyen he thong. Moi ham tra ve true neu da duoc cap, khong bao gio nem loi.
class SystemPermissions implements PermissionService {
  const SystemPermissions();

  static Future<bool> _safe(Future<bool> Function() f) async {
    try {
      return await f();
    } catch (e) {
      debugPrint('Permission loi: $e');
      return false;
    }
  }

  /// BLE: Android 12+ can scan + connect; Android <= 11 can vi tri; iOS can bluetooth.
  /// permission_handler tren Android <= 11 coi bluetoothScan/Connect la granted
  /// nen xin them vi tri (manifest chi khai bao toi SDK 30).
  @override
  Future<bool> requestBle() => _safe(() async {
        if (Platform.isIOS) {
          return (await Permission.bluetooth.request()).isGranted;
        }
        if (!Platform.isAndroid) return false;
        final res = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();
        return (res[Permission.bluetoothScan]?.isGranted ?? false) &&
            (res[Permission.bluetoothConnect]?.isGranted ?? false);
      });

  @override
  Future<bool> requestCamera() =>
      _safe(() async => (await Permission.camera.request()).isGranted);

  @override
  Future<bool> requestNotifications() =>
      _safe(() => AlertNotifications().requestPermissions());

  /// Chi Android: mien toi uu pin de service nen khong bi giet.
  @override
  Future<bool> requestIgnoreBatteryOptimizations() => _safe(() async {
        if (!Platform.isAndroid) return false;
        return (await Permission.ignoreBatteryOptimizations.request())
            .isGranted;
      });

  @override
  Future<bool> isIgnoringBatteryOptimizations() => _safe(() async {
        if (!Platform.isAndroid) return false;
        return Permission.ignoreBatteryOptimizations.isGranted;
      });
}
