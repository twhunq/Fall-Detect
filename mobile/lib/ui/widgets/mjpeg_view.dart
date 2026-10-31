import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/mjpeg_client.dart';
import '../theme.dart';

/// Xem trực tiếp luồng MJPEG của camera; bấm nút để bắt đầu/dừng.
class MjpegView extends StatefulWidget {
  const MjpegView({super.key, required this.uri});

  final Uri uri;

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  StreamSubscription<Uint8List>? _sub;
  Uint8List? _frame;
  String? _error;
  bool _running = false;

  void _start() {
    _sub?.cancel();
    setState(() {
      _running = true;
      _error = null;
    });
    _sub = openMjpeg(widget.uri).listen(
      (f) {
        if (mounted) setState(() => _frame = f);
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _error = 'Không xem được: $e';
            _running = false;
          });
        }
      },
      onDone: () {
        if (mounted) setState(() => _running = false);
      },
      cancelOnError: true,
    );
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    if (mounted) setState(() => _running = false);
  }

  @override
  void didUpdateWidget(MjpegView old) {
    super.didUpdateWidget(old);
    if (old.uri != widget.uri && _running) _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.statusColors.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: _frame == null
                ? Text(_running ? 'Đang kết nối…' : 'Chưa phát',
                    style: TextStyle(color: muted))
                : Image.memory(_frame!, gaplessPlayback: true, fit: BoxFit.contain),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: TextStyle(color: context.statusColors.bad)),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _running ? _stop : _start,
              icon: Icon(_running ? Icons.stop : Icons.play_arrow),
              label: Text(_running ? 'Dừng xem' : 'Xem trực tiếp'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.uri.toString(),
                  overflow: TextOverflow.ellipsis, style: TextStyle(color: muted)),
            ),
          ],
        ),
      ],
    );
  }
}
