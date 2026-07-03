import 'package:shared_preferences/shared_preferences.dart';

/// Gestiona la URL base del servidor MicoScan.
/// La URL se persiste en SharedPreferences y puede cambiarse desde la app.
class MaApiConfig {
  static const String _kPrefKey   = 'micoscan_api_url';
  static const String _kDefaultUrl =
      'https://karma-herald-ecosphere.ngrok-free.dev';

  static String _cachedUrl = _kDefaultUrl;
  static bool   _loaded    = false;

  /// Carga la URL guardada. Llamar una vez al arrancar la app.
  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _cachedUrl = prefs.getString(_kPrefKey) ?? _kDefaultUrl;
    _loaded = true;
  }

  /// URL base actual (sin slash final).
  static String get baseUrl => _cachedUrl;

  /// Actualiza y persiste la nueva URL.
  static Future<void> setBaseUrl(String url) async {
    final clean = url.trimRight().replaceAll(RegExp(r'/+$'), '');
    _cachedUrl = clean;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, clean);
  }

  /// Restaura la URL por defecto.
  static Future<void> resetToDefault() async {
    await setBaseUrl(_kDefaultUrl);
  }
}
