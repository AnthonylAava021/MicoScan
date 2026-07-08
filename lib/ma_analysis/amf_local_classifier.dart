import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import 'dart:ui';
import 'ma_models.dart';

/// Clasificador local offline — Mask R-CNN de la API exportado como ONNX.
///
/// Preprocesamiento NCHW con rango [0, 1] (sin normalización manual, el modelo la hace interna).
///
/// Output:
///   - 'boxes': [num_detections, 4] -> [xmin, ymin, xmax, ymax]
///   - 'labels': [num_detections] -> indices de clase
///   - 'scores': [num_detections] -> confianzas
class AmfLocalClassifier {
  AmfLocalClassifier._();
  static final AmfLocalClassifier instance = AmfLocalClassifier._();

  static const _assetPath = 'assets/models/modelo_amf.onnx';
  static const _inputSize = 512;
  static const _classes = ["__background__", "arbuscule", "vesicle", "hypha"];

  OrtSession? _session;
  bool _cargando = false;

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
      final modelFile = await _extractModelFile();
      debugPrint('[AmfClassifier] Cargando detector ONNX desde: ${modelFile.path}');
      final opts = OrtSessionOptions();
      await Future<void>.delayed(const Duration(milliseconds: 16));
      _session = OrtSession.fromFile(modelFile, opts);
      opts.release();
      debugPrint('[AmfClassifier] ✓ Modelo listo. inputs=${_session!.inputNames} outputs=${_session!.outputNames}');
    } catch (e, st) {
      debugPrint('[AmfClassifier] ✗ Error al cargar: $e\n$st');
      rethrow;
    } finally {
      _cargando = false;
    }
  }

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

  /// Ejecuta detección de objetos en la imagen local.
  Future<List<MaBoundingBox>> detectObjects(img.Image source, {double threshold = 0.05}) async {
    if (_session == null) {
      throw StateError('[AmfClassifier] El detector no está inicializado.');
    }

    // Preprocesar en Isolate (rango [0, 1] sin normalización ImageNet)
    final tensor = await compute(_buildTensor, _PreprocInput(source, _inputSize));

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

    final outputNames = _session!.outputNames;
    OrtValue? boxesVal;
    OrtValue? labelsVal;
    OrtValue? scoresVal;

    for (int i = 0; i < outputNames.length; i++) {
      final name = outputNames[i];
      if (name == 'boxes') boxesVal = outputs[i];
      if (name == 'labels') labelsVal = outputs[i];
      if (name == 'scores') scoresVal = outputs[i];
    }

    if (boxesVal == null || labelsVal == null || scoresVal == null) {
      for (final out in outputs) {
        out?.release();
      }
      throw StateError('[AmfClassifier] Faltan salidas en el modelo detector.');
    }

    final rawBoxes = _extractDouble2D(boxesVal.value);
    final rawLabels = _extractInt1D(labelsVal.value);
    final rawScores = _extractDouble1D(scoresVal.value);

    // Liberar outputs
    for (final out in outputs) {
      out?.release();
    }

    final detections = <MaBoundingBox>[];
    final numDetections = rawScores.length;

    for (int i = 0; i < numDetections; i++) {
      final score = rawScores[i];
      final labelIdx = rawLabels[i];
      if (labelIdx < 1 || labelIdx >= _classes.length) continue;

      // Umbrales calibrados altamente sensibles para emular la densidad de la API de forma local
      double minScore = 0.08; // arbuscule (1)
      if (labelIdx == 2) minScore = 0.03; // vesicle (2)
      if (labelIdx == 3) minScore = 0.06; // hypha (3)

      if (score < minScore) continue;

      final labelName = _classes[labelIdx];
      final box = rawBoxes[i];

      // Escalar de la resolución del modelo (512x512) al espacio de referencia (224x224)
      const scale = 224.0 / 512.0;
      final x1 = box[0] * scale;
      final y1 = box[1] * scale;
      final x2 = box[2] * scale;
      final y2 = box[3] * scale;

      detections.add(MaBoundingBox(
        estructura: labelName,
        confianza: score,
        rect: Rect.fromLTRB(x1, y1, x2, y2),
      ));
    }

    return detections;
  }

  static Float32List _buildTensor(_PreprocInput p) {
    final resized = img.copyResize(
      p.source,
      width: p.size,
      height: p.size,
      interpolation: img.Interpolation.linear,
    );
    final planeSize = p.size * p.size;
    final buf = Float32List(3 * planeSize);
    
    // Normalización de ImageNet requerida por el modelo detector entrenado
    const mean = [0.485, 0.456, 0.406];
    const std  = [0.229, 0.224, 0.225];

    int idx = 0;
    for (final pixel in resized) {
      buf[idx] = (pixel.r / 255.0 - mean[0]) / std[0];
      buf[planeSize + idx] = (pixel.g / 255.0 - mean[1]) / std[1];
      buf[2 * planeSize + idx] = (pixel.b / 255.0 - mean[2]) / std[2];
      idx++;
      if (idx >= planeSize) break;
    }
    return buf;
  }

  List<List<double>> _extractDouble2D(dynamic raw) {
    if (raw is List<List<double>>) return raw;
    if (raw is List) {
      return raw.map<List<double>>((row) {
        if (row is List) {
          return row.map<double>((v) => (v as num).toDouble()).toList();
        }
        return [(row as num).toDouble()];
      }).toList();
    }
    return [];
  }

  List<int> _extractInt1D(dynamic raw) {
    if (raw is List<int>) return raw;
    if (raw is Int64List) return raw.toList();
    if (raw is List) {
      return raw.map<int>((v) => (v as num).toInt()).toList();
    }
    return [];
  }

  List<double> _extractDouble1D(dynamic raw) {
    if (raw is List<double>) return raw;
    if (raw is Float32List) return raw.toList();
    if (raw is List) {
      return raw.map<double>((v) => (v as num).toDouble()).toList();
    }
    return [];
  }

  void dispose() {
    _session?.release();
    _session = null;
  }
}

class _PreprocInput {
  final img.Image source;
  final int size;
  const _PreprocInput(this.source, this.size);
}
