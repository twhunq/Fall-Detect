/// Hằng số cấu hình dùng chung (khớp cloud/public/config.js và firmware).
class AppConfig {
  const AppConfig._();

  // Firebase (giá trị công khai, quyền truy cập do database.rules.json kiểm soát).
  static const String firebaseApiKey = 'AIzaSyCMpi-CSCgvlx8w1WlW1wPzMT3qV2eld5A';
  static const String firebaseDatabaseUrl =
      'https://fall-detect-26023-default-rtdb.asia-southeast1.firebasedatabase.app';
  static const String firebaseProjectId = 'fall-detect-26023';

  static const String defaultDeviceId = 'baonga-01';

  /// Cổng UDP quảng bá cảnh báo trong mạng LAN.
  static const int udpPort = 4210;

  // BLE (camera cầu nối).
  static const String bleServiceUuid = 'a8f3d100-1b2c-4e5f-9a7b-3c6d8e0f1234';
  static const String bleAlertUuid = 'a8f3d101-1b2c-4e5f-9a7b-3c6d8e0f1234';
  static const String bleStatusUuid = 'a8f3d102-1b2c-4e5f-9a7b-3c6d8e0f1234';
  static const String bleAuthUuid = 'a8f3d103-1b2c-4e5f-9a7b-3c6d8e0f1234';
  static const String bleConfigUuid = 'a8f3d104-1b2c-4e5f-9a7b-3c6d8e0f1234';
  static const String bleInfoUuid = 'a8f3d105-1b2c-4e5f-9a7b-3c6d8e0f1234';
  static const int manufacturerId = 0xFFFF;
  static const int deviceTypeCamera = 2;

  // Vòng đeo trong mạng LAN.
  static const String wearableMdnsUrl = 'http://baonga.local';
  static const String wearableHotspotUrl = 'http://192.168.4.1';

  /// Hai nguồn khác nhau báo ngã trong khoảng này được gộp thành một sự cố.
  static const Duration fusionWindow = Duration(seconds: 30);

  /// Sự cố đã xác nhận chỉ nhận bản sao muộn trong khoảng này (từ lúc bắt đầu).
  static const Duration lateCopyWindow = Duration(seconds: 20);

  /// Cùng nguồn, cùng loại trong khoảng này bị coi là bản sao.
  static const Duration dedupeWindow = Duration(seconds: 60);
}
