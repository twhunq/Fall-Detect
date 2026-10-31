import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/protocol/mjpeg_splitter.dart';

/// Mở luồng MJPEG và phát từng ảnh JPEG. Hủy subscription sẽ đóng kết nối.
Stream<Uint8List> openMjpeg(Uri uri, {http.Client? client}) {
  final http.Client c = client ?? http.Client();
  final ownsClient = client == null;
  final abort = Completer<void>();
  late final StreamController<Uint8List> controller;
  StreamSubscription<List<int>>? sub;

  void shutdown() {
    if (!abort.isCompleted) abort.complete();
    if (ownsClient) c.close();
  }

  Future<void> run() async {
    try {
      final req = http.AbortableRequest('GET', uri, abortTrigger: abort.future);
      final res = await c.send(req).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw http.ClientException('HTTP ${res.statusCode}', uri);
      }
      final boundary =
          MjpegSplitter.boundaryFromContentType(res.headers['content-type'] ?? '') ?? 'k230';
      final splitter = MjpegSplitter(boundary: boundary);
      sub = res.stream.listen(
        (chunk) {
          for (final frame in splitter.add(chunk)) {
            if (!controller.isClosed) controller.add(frame);
          }
        },
        onError: (Object e, StackTrace st) {
          if (!controller.isClosed) controller.addError(e, st);
        },
        onDone: () {
          if (!controller.isClosed) unawaited(controller.close());
        },
        cancelOnError: true,
      );
    } catch (e, st) {
      if (!controller.isClosed) {
        controller.addError(e, st);
        unawaited(controller.close());
      }
    }
  }

  controller = StreamController<Uint8List>(
    onListen: () => unawaited(run()),
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () async {
      shutdown();
      await sub?.cancel();
    },
  );
  return controller.stream;
}
