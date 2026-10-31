import 'dart:convert';
import 'dart:typed_data';

enum _State { searching, headers, body }

/// Tách luồng multipart/x-mixed-replace thành từng ảnh JPEG, tăng dần theo chunk.
///
/// Phần: `--k230\r\nContent-Type: image/jpeg\r\nContent-Length: N\r\n\r\n<N byte>\r\n`.
/// Dùng Content-Length nếu có, nếu không thì quét tới JPEG EOI (FF D9).
class MjpegSplitter {
  MjpegSplitter({String boundary = 'k230', this.maxBuffer = 2 * 1024 * 1024})
      : _marker = ascii.encode('--$boundary');

  /// Giới hạn bộ đệm để không phình vô hạn khi luồng hỏng.
  final int maxBuffer;
  final Uint8List _marker;

  Uint8List _buf = Uint8List(0);
  _State _state = _State.searching;
  int _contentLength = -1;

  /// Lấy boundary từ giá trị header Content-Type.
  static String? boundaryFromContentType(String contentType) {
    final m = RegExp(r'boundary\s*=\s*(?:"([^"]+)"|([^;\s]+))', caseSensitive: false)
        .firstMatch(contentType);
    if (m == null) return null;
    return m.group(1) ?? m.group(2);
  }

  /// Nạp thêm dữ liệu, trả về các ảnh JPEG hoàn chỉnh (có thể rỗng).
  List<Uint8List> add(List<int> chunk) {
    if (chunk.isNotEmpty) {
      final merged = Uint8List(_buf.length + chunk.length)
        ..setRange(0, _buf.length, _buf)
        ..setRange(_buf.length, _buf.length + chunk.length, chunk);
      _buf = merged;
    }
    final frames = <Uint8List>[];
    while (_step(frames)) {}
    if (_buf.length > maxBuffer) _reset();
    return frames;
  }

  void _reset() {
    _buf = Uint8List(0);
    _state = _State.searching;
    _contentLength = -1;
  }

  void _drop(int n) {
    _buf = Uint8List.sublistView(_buf, n);
  }

  /// Xử lý một bước; trả về true nếu còn có thể tiến tiếp.
  bool _step(List<Uint8List> frames) {
    switch (_state) {
      case _State.searching:
        final i = _indexOf(_marker, 0);
        if (i < 0) {
          final keep = _marker.length - 1;
          if (_buf.length > keep) _drop(_buf.length - keep);
          return false;
        }
        _drop(i + _marker.length);
        _state = _State.headers;
        return true;
      case _State.headers:
        final end = _indexOf(const [13, 10, 13, 10], 0);
        if (end < 0) {
          if (_buf.length > 8192) _reset();
          return false;
        }
        final text = latin1.decode(_buf.sublist(0, end));
        _contentLength = -1;
        for (final line in text.split('\n')) {
          final colon = line.indexOf(':');
          if (colon > 0 &&
              line.substring(0, colon).trim().toLowerCase() == 'content-length') {
            _contentLength = int.tryParse(line.substring(colon + 1).trim()) ?? -1;
          }
        }
        _drop(end + 4);
        if (_contentLength > maxBuffer) {
          _reset();
          return false;
        }
        _state = _State.body;
        return true;
      case _State.body:
        if (_contentLength >= 0) {
          if (_buf.length < _contentLength) return false;
          frames.add(Uint8List.fromList(_buf.sublist(0, _contentLength)));
          _drop(_contentLength);
        } else {
          final e = _indexOf(const [0xFF, 0xD9], 0);
          if (e < 0) return false;
          frames.add(Uint8List.fromList(_buf.sublist(0, e + 2)));
          _drop(e + 2);
        }
        _state = _State.searching;
        return true;
    }
  }

  int _indexOf(List<int> pattern, int from) {
    final n = _buf.length - pattern.length;
    for (var i = from; i <= n; i++) {
      var j = 0;
      while (j < pattern.length && _buf[i + j] == pattern[j]) {
        j++;
      }
      if (j == pattern.length) return i;
    }
    return -1;
  }
}
