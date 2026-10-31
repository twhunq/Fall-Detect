import 'package:flutter/material.dart';

import 'widgets/mjpeg_view.dart';

/// Xem camera toàn trang (nền tối cố định).
class CameraLivePage extends StatelessWidget {
  const CameraLivePage({super.key, required this.uri, required this.name});

  final Uri uri;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Quay lại',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.chevron_left_rounded, size: 30, color: Colors.white),
                    style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
                        const Row(
                          children: [
                            CircleAvatar(radius: 4, backgroundColor: Color(0xFFF04438)),
                            SizedBox(width: 6),
                            Text('Trực tiếp',
                                style: TextStyle(fontSize: 13, color: Color(0xFFA9B3C6))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: MjpegView(uri: uri, retryOnTap: true),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.verified_user_outlined,
                            size: 18, color: Color(0xFF6EA2F5)),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('Camera đang tự động phát hiện ngã.',
                            style: TextStyle(
                                fontSize: 15, height: 22 / 15, color: Color(0xFFD5DBE6))),
                      ),
                    ],
                  ),
                  SizedBox(height: 14),
                  Text('Chỉ xem được hình khi điện thoại dùng chung Wi-Fi với camera.',
                      style: TextStyle(
                          fontSize: 13, height: 19 / 13, color: Color(0xFFA9B3C6))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
