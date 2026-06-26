import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

/// Clasificador local offline — ResNet-50 exportado como ONNX.
///
/// Preprocesamiento NCHW con normalización ImageNet:
///   R = (R/255 − 0.485) / 0.229
///   G = (G/255 − 0.456) / 0.224
///   B = (B/255 − 0.406) / 0.225
///
/// Output 'logits': [1,4] → [background=0, arbuscule=1, vesicle=2, hypha=3]
class AmfLocalClassifier {
  AmfLocalClassifier._();
  static final AmfLocalClassifier instance = AmfLocalClassifier._();

  static const _assetPath = 'assets/models/modelo_amf.onnx';
  static const _inputSize = 512;
  static const _mean = [0.485, 0.456, 0.406];
  static const _std  = [0.229, 0.224, 0.225];

  OrtSession? _session;
  bool _cargando = false;

  // ───────────────────────────────────────────────────────────────────────────
  // Carga del modelo
  // ───────────────────────────────────────────────────────────────────────────

  /// Carga el modelo (idempotente). El archivo se extrae de los assets a un
  /// directorio de documentos la primera vez y luego se usa [OrtSession.fromFile],
  /// evitando cargar 94 MB en RAM como Uint8List.
  Future<void> load() async {
    if (_session != null) return;
    if (_cargando) {
      while (_cargando) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    _cargando = true;
    try {
      OrtEnv.instance.init();

      // Extraer el asset a un File local la primera vez
      final modelFile = await _extractModelFile();

      debugPrint('[AmfClassifier] Cargando modelo desde: ${modelFile.path}');
      final opts = OrtSessionOptions();

      // Ceder un frame a la UI antes de que fromFile() bloquee el hilo principal.
      await Future<void>.delayed(const Duration(milliseconds: 16));

      _session = OrtSession.fromFile(modelFile, opts);
      opts.release();

      debugPrint('[AmfClassifier] ✓ Modelo listo. '
          'inputs=${_session!.inputNames} outputs=${_session!.outputNames}');
    } catch (e, st) {
      debugPrint('[AmfClassifier] ✗ Error al cargar: $e\n$st');
      rethrow;
    } finally {
      _cargando = false;
    }
  }

  /// Extrae el asset ONNX al directorio de documentos (una sola vez).
  /// Verifica el tamaño exacto para detectar extracciones incompletas.
  Future<File> _extractModelFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/modelo_amf.onnx');

    final byteData = await rootBundle.load(_assetPath);
    final expectedSize = byteData.lengthInBytes;

    if (await file.exists() && await file.length() == expectedSize) {
      debugPrint('[AmfClassifier] Modelo ya extraído ($expectedSize bytes) ✓');
      return file;
    }

    debugPrint('[AmfClassifier] Extrayendo modelo: $expectedSize bytes → ${file.path}');
    await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    debugPrint('[AmfClassifier] Extracción completa ✓');
    return file;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Clasificación
  // ───────────────────────────────────────────────────────────────────────────

  /// Clasifica [source]. Retorna probabilidades softmax:
  ///   { 'arbuscule': 0.xx, 'vesicle': 0.xx, 'hypha': 0.xx }
  Future<Map<String, double>> classifyImage(img.Image source) async {
    if (_session == null) await load();

    // Preprocesar en Isolate — 786 432 operaciones float, no bloquear UI
    final tensor = await compute(_buildTensor, _PreprocInput(source, _inputSize, _mean, _std));

    final inputName = _session!.inputNames.first;
    final input = OrtValueTensor.createTensorWithDataList(
      tensor,
      [1, 3, _inputSize, _inputSize],
    );

    final runOptions = OrtRunOptions();
    List<OrtValue?> outputs;
    try {
      outputs = _session!.run(runOptions, {inputName: input});
    } catch (e) {
      debugPrint('[AmfClassifier] Error en run(): $e');
      rethrow;
    } finally {
      input.release();
      runOptions.release();
    }

    final outputValue = outputs.first;
    if (outputValue == null) {
      throw StateError('[AmfClassifier] output nulo tras inferencia.');
    }

    final logits = _extractLogits(outputValue.value);
    outputValue.release();

    debugPrint('[AmfClassifier] logits=$logits');
    final probs = _softmax(logits);
    debugPrint('[AmfClassifier] probs=$probs');

    return {
      'arbuscule': probs[1],
      'vesicle':   probs[2],
      'hypha':     probs[3],
    };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helpers privados
  // ───────────────────────────────────────────────────────────────────────────

  /// Preprocesamiento ejecutado en un Isolate separado.
  static Float32List _buildTensor(_PreprocInput p) {
    final resized = img.copyResize(
      p.source,
      width: p.size,
      height: p.size,
      interpolation: img.Interpolation.linear,
    );
    final planeSize = p.size * p.size;
    final buf = Float32List(3 * planeSize);
    for (var y = 0; y < p.size; y++) {
      for (var x = 0; x < p.size; x++) {
        final px = resized.getPixel(x, y);
        final i = y * p.size + x;
        buf[i]                = (px.r / 255.0 - p.mean[0]) / p.std[0];
        buf[planeSize + i]    = (px.g / 255.0 - p.mean[1]) / p.std[1];
        buf[2 * planeSize + i]= (px.b / 255.0 - p.mean[2]) / p.std[2];
      }
    }
    return buf;
  }

  /// Extrae logits del valor de salida independientemente del tipo exacto.
  List<double> _extractLogits(dynamic raw) {
    if (raw is List<List<double>>) return raw.first;
    if (raw is List<double>) return raw;
    // Fallback para cualquier otro tipo anidado
    final flat = <double>[];
    for (final item in raw as List) {
      if (item is List) {
        flat.addAll(item.map<double>((v) => (v as num).toDouble()));
      } else {
        flat.add((item as num).toDouble());
      }
    }
    return flat;
  }

  static List<double> _softmax(List<double> logits) {
    final maxL = logits.reduce(math.max);
    final exp  = logits.map((v) => math.exp(v - maxL)).toList();
    final sum  = exp.reduce((a, b) => a + b);
    return exp.map((v) => v / sum).toList();
  }

  /// Libera la sesión ONNX.
  void dispose() {
    _session?.release();
    _session = null;
  }
}

// Clase auxiliar para pasar parámetros al Isolate (compute requiere un único arg)
class _PreprocInput {
  final img.Image source;
  final int size;
  final List<double> mean;
  final List<double> std;
  const _PreprocInput(this.source, this.size, this.mean, this.std);
}
