/// Một sự kiện Server-Sent Events.
class SseEvent {
  const SseEvent(this.event, this.data);
  final String event;
  final String data;

  @override
  String toString() => 'SseEvent($event, $data)';
}

/// Bộ phân tích SSE theo W3C, nhận chuỗi theo từng đoạn tùy ý.
class SseParser {
  String _pending = '';
  String _event = '';
  final List<String> _data = [];

  List<SseEvent> add(String chunk) {
    _pending += chunk;
    final out = <SseEvent>[];
    var start = 0;
    var i = 0;
    while (i < _pending.length) {
      final c = _pending.codeUnitAt(i);
      if (c == 0x0A || c == 0x0D) {
        // '\r' cuối bộ đệm có thể đi kèm '\n' ở đoạn sau: chờ.
        if (c == 0x0D && i + 1 >= _pending.length) break;
        _line(_pending.substring(start, i), out);
        if (c == 0x0D && _pending.codeUnitAt(i + 1) == 0x0A) i++;
        start = i + 1;
      }
      i++;
    }
    _pending = _pending.substring(start);
    return out;
  }

  void _line(String line, List<SseEvent> out) {
    if (line.isEmpty) {
      if (_data.isNotEmpty) {
        out.add(SseEvent(_event.isEmpty ? 'message' : _event, _data.join('\n')));
      }
      _event = '';
      _data.clear();
      return;
    }
    if (line.startsWith(':')) return;
    final colon = line.indexOf(':');
    final String field;
    var value = '';
    if (colon < 0) {
      field = line;
    } else {
      field = line.substring(0, colon);
      value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
    }
    if (field == 'event') {
      _event = value;
    } else if (field == 'data') {
      _data.add(value);
    }
  }
}

/// Cây JSON dựng lại từ các sự kiện put/patch của Firebase RTDB.
class JsonTree {
  dynamic root;

  List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  void applyPut(String path, dynamic data) {
    final seg = _segments(path);
    data = _clone(data);
    if (seg.isEmpty) {
      root = data;
      return;
    }
    if (root is! Map) {
      if (data == null) return;
      root = <String, dynamic>{};
    }
    _put(root as Map<String, dynamic>, seg, 0, data);
    if ((root as Map).isEmpty) root = null;
  }

  /// Sao chép sâu để mọi Map trong cây đều là `Map<String, dynamic>`.
  static dynamic _clone(dynamic v) {
    if (v is Map) return {for (final e in v.entries) e.key.toString(): _clone(e.value)};
    if (v is List) return v.map(_clone).toList();
    return v;
  }

  void applyPatch(String path, Map<dynamic, dynamic> data) {
    final base = path.endsWith('/') ? path : '$path/';
    data.forEach((k, v) => applyPut('$base$k', v));
  }

  /// Ghi/xóa giá trị tại [seg]; nhánh rỗng sau khi xóa bị gỡ khỏi cha.
  void _put(Map<String, dynamic> node, List<String> seg, int i, dynamic data) {
    final key = seg[i];
    if (i == seg.length - 1) {
      if (data == null) {
        node.remove(key);
      } else {
        node[key] = data;
      }
      return;
    }
    var child = node[key];
    if (child is! Map) {
      if (data == null) return;
      child = <String, dynamic>{};
      node[key] = child;
    }
    _put(child as Map<String, dynamic>, seg, i + 1, data);
    if (child.isEmpty) node.remove(key);
  }
}
