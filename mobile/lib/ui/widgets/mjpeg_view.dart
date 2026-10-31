import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/mjpeg_client.dart';

/// Khung xem luồng MJPEG, tự phát khi hiển thị và tự dừng khi bị che/ẩn.
/// Lấp đầy khung cha (đặt trong AspectRatio/SizedBox).
class MjpegView extends StatefulWidget {
  const MjpegView({
    super.key,
    required this.uri,
    this.label,
    this.active = true,
    this.showExpandIcon = false,
    this.retryOnTap = false,
    this.placeholderColor = const Color(0xFF8C97AB),
  });

  final Uri uri;

  /// Tên hiển thị góc dưới trái.
  final String? label;

  /// false: tạm dừng (ví dụ tab đang ẩn).
  final bool active;
  final bool showExpandIcon;

  /// Chạm để thử lại khi lỗi.
  final bool retryOnTap;
  final Color placeholderColor;

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  StreamSubscription<Uint8List>? _sub;
  Uint8List? _frame;
  bool _failed = false;
  bool _tickerOn = true;

  bool get _shouldRun => widget.active && _tickerOn && !_failed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Route khác phủ lên thì TickerMode tắt: dừng luồng để camera chỉ phục vụ một người xem.
    final on = TickerMode.valuesOf(context).enabled;
    if (on && !_tickerOn) _failed = false;
    _tickerOn = on;
    _sync();
  }

  @override
  void didUpdateWidget(MjpegView old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _failed = false;
    if (old.uri != widget.uri) {
      _stop();
      _failed = false;
    }
    _sync();
  }

  void _sync() {
    if (_shouldRun && _sub == null) {
      _start();
    } else if (!(widget.active && _tickerOn) && _sub != null) {
      _stop();
    }
  }

  void _start() {
    _sub = openMjpeg(widget.uri).listen(
      (f) {
        if (mounted) setState(() => _frame = f);
      },
      onError: (Object _) {
        _sub = null;
        if (mounted) {
          setState(() {
            _failed = true;
            _frame = null;
          });
        }
      },
      onDone: () {
        _sub = null;
        if (mounted) setState(() => _failed = true);
      },
      cancelOnError: true,
    );
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
  }

  void _retry() {
    setState(() => _failed = false);
    _sync();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = _frame != null && _sub != null;
    final child = Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF1C2535)),
        if (_frame != null)
          Image.memory(_frame!, gaplessPlayback: true, fit: BoxFit.cover)
        else
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_failed ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                    size: 30, color: widget.placeholderColor),
                const SizedBox(height: 8),
                Text(
                  _failed
                      ? (widget.retryOnTap
                          ? 'Không xem được. Chạm để thử lại.'
                          : 'Không xem được hình')
                      : 'Đang kết nối…',
                  style: TextStyle(fontSize: 13, color: widget.placeholderColor),
                ),
              ],
            ),
          ),
        if (live)
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0x9E0E1525),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(radius: 4, backgroundColor: Color(0xFFF04438)),
                  SizedBox(width: 6),
                  Text('Trực tiếp',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ),
            ),
          ),
        if (widget.label != null)
          Positioned(
            left: 12,
            bottom: 12,
            child: Text(widget.label!,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        if (widget.showExpandIcon)
          Positioned(
            right: 12,
            bottom: 10,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0x9E0E1525),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.open_in_full_rounded, size: 18, color: Colors.white),
            ),
          ),
      ],
    );
    if (widget.retryOnTap && _failed) {
      return GestureDetector(onTap: _retry, child: child);
    }
    return child;
  }
}
