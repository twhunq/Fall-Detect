import 'package:bao_nga_iot/core/protocol/sse_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SseParser', () {
    test('basic events and keep-alive', () {
      final p = SseParser();
      final ev = p.add('event: put\ndata: {"path":"/","data":1}\n\n'
          'event: keep-alive\ndata: null\n\n');
      expect(ev.map((e) => e.event), ['put', 'keep-alive']);
      expect(ev.first.data, '{"path":"/","data":1}');
    });

    test('multi-line data, comments, default event, CRLF', () {
      final ev = SseParser().add(': comment\r\ndata: a\r\ndata: b\r\n\r\ndata:x\r\n\r\n');
      expect(ev.length, 2);
      expect(ev[0].event, 'message');
      expect(ev[0].data, 'a\nb');
      expect(ev[1].data, 'x');
    });

    test('chunks split anywhere', () {
      const text = 'event: put\r\ndata: {"a":1}\r\n\r\nevent: patch\ndata: {"b":2}\n\n';
      for (var cut = 0; cut <= text.length; cut++) {
        final p = SseParser();
        final ev = [...p.add(text.substring(0, cut)), ...p.add(text.substring(cut))];
        expect(ev.map((e) => '${e.event}:${e.data}'), ['put:{"a":1}', 'patch:{"b":2}'],
            reason: 'cut=$cut');
      }
    });

    test('event without data is not dispatched', () {
      expect(SseParser().add('event: x\n\n'), isEmpty);
    });
  });

  group('JsonTree', () {
    test('put at root and nested path', () {
      final t = JsonTree();
      t.applyPut('/', {'status': {'alarm': 'off', 'inactive': false}, 'info': {'name': 'A'}});
      expect(t.root['status']['alarm'], 'off');
      t.applyPut('/status/alarm', 'fall');
      expect(t.root['status']['alarm'], 'fall');
      expect(t.root['info']['name'], 'A');
      t.applyPut('/control/settings/chatIds', '1');
      expect(t.root['control']['settings']['chatIds'], '1');
    });

    test('null deletes and prunes empty parents', () {
      final t = JsonTree();
      t.applyPut('/', {'a': {'b': 1}, 'c': 2});
      t.applyPut('/a/b', null);
      expect(t.root.containsKey('a'), isFalse);
      expect(t.root['c'], 2);
      t.applyPut('/', null);
      expect(t.root, isNull);
    });

    test('patch merges keys', () {
      final t = JsonTree();
      t.applyPut('/', {'status': {'alarm': 'off', 'rssi': -50}});
      t.applyPatch('/status', {'alarm': 'fall', 'rssi': null, 'ip': '1.2.3.4'});
      expect(t.root['status'], {'alarm': 'fall', 'ip': '1.2.3.4'});
      t.applyPatch('/', {'info': {'name': 'B'}});
      expect(t.root['info']['name'], 'B');
    });

    test('put into empty tree', () {
      final t = JsonTree();
      t.applyPut('/status/alarm', 'fall');
      expect(t.root, {'status': {'alarm': 'fall'}});
    });
  });
}
