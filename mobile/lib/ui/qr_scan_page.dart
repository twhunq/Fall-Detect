import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/protocol/ble_protocol.dart';

/// Quét mã QR ghép nối cbn://pair?... và trả về chuỗi hợp lệ qua Navigator.pop.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller =
      MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final text = b.rawValue;
      if (text == null) continue;
      if (parsePairingUri(text) != null) {
        _done = true;
        Navigator.of(context).pop(text);
        return;
      }
    }
    if (capture.barcodes.isNotEmpty) {
      setState(() => _hint = 'Mã QR này không phải mã ghép nối camera.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quét QR ghép nối')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Không mở được camera (${error.errorCode.name}). Hãy cấp quyền camera hoặc nhập mã thủ công.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _hint ?? 'Hướng camera điện thoại vào mã QR dán trên thiết bị camera AI.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
