import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ma_models.dart';

/// RF-08: historial de análisis en almacenamiento local.
class MaHistoryStorage {
  static const _key = 'ma_analisis_historial_v1';

  static Future<List<MaHistorialItem>> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => MaHistorialItem.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));
  }

  static Future<void> guardar(MaHistorialItem item) async {
    final items = await cargar();
    items.removeWhere((e) => e.id == item.id);
    items.insert(0, item);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> eliminar(String id) async {
    final items = await cargar();
    items.removeWhere((e) => e.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }
}
