import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_nga_iot/core/protocol/mjpeg_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List jpeg(int seed, int size) {
  final b = Uint8List(size);
  for (var i = 0; i < size; i++) {
    b[i] = (seed + i * 7) & 0xFF;
    if (b[i] == 0xFF) b[i] = 0xFE; // tránh FF D9 giả giữa ảnh
  }
  b[0] = 0xFF;
  b[1] = 0xD8;
  b[size - 2] = 0xFF;
  b[size - 1] = 0xD9;
  return b;
}

List<int> part(Uint8List frame, {bool withLength = true}) => [
      ...ascii.encode('--k230\r\nContent-Type: image/jpeg\r\n'),
      if (withLength) ...ascii.encode('Content-Length: ${frame.length}\r\n'),
      ...ascii.encode('\r\n'),
      ...frame,
      ...ascii.encode('\r\n'),
    ];

void main() {
  final f1 = jpeg(1, 300), f2 = jpeg(2, 500), f3 = jpeg(3, 64);

  test('frames with Content-Length, one chunk', () {
    final out = MjpegSplitter().add([...part(f1), ...part(f2), ...part(f3)]);
    expect(out, [f1, f2, f3]);
  });

  test('frames without Content-Length use EOI', () {
    final out = MjpegSplitter().add([...part(f1, withLength: false), ...part(f2, withLength: false)]);
    expect(out, [f1, f2]);
  });

  for (final withLength in [true, false]) {
    test('split at every byte offset (length=$withLength)', () {
      final stream = [
        ...ascii.encode('garbage\r\n'),
        ...part(f1, withLength: withLength),
        ...part(f2, withLength: withLength),
      ];
      for (var cut = 0; cut <= stream.length; cut++) {
        final s = MjpegSplitter();
        final out = [...s.add(stream.sublist(0, cut)), ...s.add(stream.sublist(cut))];
        expect(out, [f1, f2], reason: 'cut=$cut');
      }
    });
  }

  test('byte by byte', () {
    final s = MjpegSplitter();
    final out = <Uint8List>[];
    for (final b in [...part(f1), ...part(f2)]) {
      out.addAll(s.add([b]));
    }
    expect(out, [f1, f2]);
  });

  test('garbage prefix is skipped', () {
    final out = MjpegSplitter().add([...List.filled(50, 0x41), ...part(f1)]);
    expect(out, [f1]);
  });

  test('custom boundary and boundaryFromContentType', () {
    expect(MjpegSplitter.boundaryFromContentType('multipart/x-mixed-replace; boundary=k230'), 'k230');
    expect(MjpegSplitter.boundaryFromContentType('multipart/x-mixed-replace;boundary="abc"'), 'abc');
    expect(MjpegSplitter.boundaryFromContentType('image/jpeg'), isNull);
    final data = ascii.encode('--xyz\r\nContent-Length: ${f1.length}\r\n\r\n');
    expect(MjpegSplitter(boundary: 'xyz').add([...data, ...f1]), [f1]);
  });

  test('buffer cap prevents unbounded growth', () {
    final s = MjpegSplitter(maxBuffer: 1000);
    // Content-Length lớn hơn giới hạn: bỏ qua phần, rồi vẫn nhận ảnh tiếp theo.
    final bad = ascii.encode('--k230\r\nContent-Length: 999999\r\n\r\n');
    expect(s.add(bad), isEmpty);
    expect(s.add(List.filled(5000, 0)), isEmpty);
    expect(s.add(part(f1)), [f1]);
  });
}
