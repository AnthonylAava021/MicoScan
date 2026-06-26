/// Singleton que almacena el último resultado de preprocesamiento
/// para que la pantalla Pipeline pueda mostrarlo automáticamente
/// cuando el usuario regresa tras un análisis.
library;

class MaPipelineStore {
  MaPipelineStore._();
  static final MaPipelineStore instance = MaPipelineStore._();

  /// Ruta de la imagen que se analizó
  String? imagePath;

  /// Resultado JSON del endpoint /api/preprocess
  Map<String, dynamic>? preprocessResult;

  /// True mientras se está cargando el preprocesamiento en background
  bool loading = false;

  /// Error si falló la llamada
  String? error;

  void reset() {
    imagePath        = null;
    preprocessResult = null;
    loading          = false;
    error            = null;
  }
}
