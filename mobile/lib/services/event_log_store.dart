import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/fusion/alert_models.dart';

/// Lưu lịch sử sự cố (JSON trong SharedPreferences), mới nhất ở đầu, tối đa 200.
class EventLogStore {
  EventLogStore({this.maxItems = 200});

  static const String prefsKey = 'event_log.v1';
  final int maxItems;

  Future<List<AlertIncident>> all() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(prefsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          if (e is Map) ?AlertIncident.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<AlertIncident> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        prefsKey, jsonEncode(items.take(maxItems).map((i) => i.toJson()).toList()));
  }

  /// Thêm sự cố mới ở đầu danh sách.
  Future<void> add(AlertIncident incident) async {
    final items = await all();
    items.removeWhere((i) => i.id == incident.id);
    items.insert(0, incident);
    await _save(items);
  }

  /// Cập nhật sự cố cùng id (thêm nếu chưa có).
  Future<void> update(AlertIncident incident) async {
    final items = await all();
    final at = items.indexWhere((i) => i.id == incident.id);
    if (at < 0) {
      items.insert(0, incident);
    } else {
      items[at] = incident;
    }
    await _save(items);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }
}
