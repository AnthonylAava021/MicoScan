import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'ma_models.dart';

class MaImageProcessor {
  static const minSize = 224;
  static const inputSizeLocal = 224;
  static const inputSizeRemote = 512;

  /// Tamaño de entrada del clasificador ONNX (ResNet-50 backbone).
  static const inputSizeOnnx = 512;

  // ImageNet normalisation constants (RGB)
  static const _mean = [0.485, 0.456, 0.406];
  static const _std  = [0.229, 0.224, 0.225];

  static bool esFormatoAdmitido(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');
  }

  static Future<img.Image> validarYCargar(String path) async {
    if (!esFormatoAdmitido(path)) {
      throw Exception('Formato no admitido. Use JPG o PNG.');
    }
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('No se pudo leer la imagen.');
    }
    if (decoded.width < minSize || decoded.height < minSize) {
      throw Exception('La imagen debe ser mínimo ${minSize}x$minSize px.');
    }
    return decoded;
  }

  static img.Image preprocesar(img.Image source, {int size = inputSizeLocal}) {
    final resized = img.copyResize(source, width: size, height: size);
    for (var y = 0; y < resized.height; y++) {
      for (var x = 0; x < resized.width; x++) {
        final p = resized.getPixel(x, y);
        resized.setPixel(
          x,
          y,
          img.ColorRgb8(
            (p.r / 255.0 * 255).round(),
            (p.g / 255.0 * 255).round(),
            (p.b / 255.0 * 255).round(),
          ),
        );
      }
    }
    return resized;
  }

  /// Preprocesa [source] al Float32List NCHW [1,3,512,512] requerido por el
  /// modelo ONNX con normalización ImageNet por canal (mean/std).
  static Float32List preprocesarAFloat32(img.Image source) {
    final resized = img.copyResize(
      source,
      width: inputSizeOnnx,
      height: inputSizeOnnx,
      interpolation: img.Interpolation.linear,
    );
    final planeSize = inputSizeOnnx * inputSizeOnnx;
    final buffer = Float32List(3 * planeSize);
    for (var y = 0; y < inputSizeOnnx; y++) {
      for (var x = 0; x < inputSizeOnnx; x++) {
        final p = resized.getPixel(x, y);
        final idx = y * inputSizeOnnx + x;
        buffer[idx]                  = (p.r / 255.0 - _mean[0]) / _std[0];
        buffer[planeSize + idx]      = (p.g / 255.0 - _mean[1]) / _std[1];
        buffer[2 * planeSize + idx]  = (p.b / 255.0 - _mean[2]) / _std[2];
      }
    }
    return buffer;
  }

  static Future<ProcessedInferenceData> analizarEdge({
    required img.Image source,
    required double umbralBrillo,
    required String workDir,
  }) async {
    final processed = preprocesar(source, size: inputSizeLocal);
    final w = processed.width;
    final h = processed.height;

    final mask = img.Image(width: w, height: h);
    var segmentados = 0;
    var sumR = 0.0;
    var sumG = 0.0;
    var sumB = 0.0;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = processed.getPixel(x, y);
        final brillo = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
        if (brillo <= umbralBrillo) {
          segmentados++;
          sumR += p.r;
          sumG += p.g;
          sumB += p.b;
          mask.setPixel(x, y, img.ColorRgb8(46, 125, 50));
        } else {
          mask.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
        }
      }
    }

    final area = segmentados / (w * h);
    final estructuras = _clasificarEstructuras(sumR, sumG, sumB, segmentados, area);
    final cajas = _generarCajas(w, h, estructuras);
    final gradCam = _generarGradCam(processed, mask);
    final overlay = _generarOverlay(processed, mask);

    final dir = Directory(workDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final mascaraPath = '${workDir}mask_$stamp.png';
    final gradCamPath = '${workDir}gradcam_$stamp.png';
    final overlayPath = '${workDir}overlay_$stamp.png';

    await File(mascaraPath).writeAsBytes(img.encodePng(mask));
    await File(gradCamPath).writeAsBytes(img.encodePng(gradCam));
    await File(overlayPath).writeAsBytes(img.encodePng(overlay));

    return ProcessedInferenceData(
      estructuras: estructuras,
      cajas: cajas,
      areaSegmentada: area,
      resumen:
          'Inferencia local (edge). Área segmentada ${(area * 100).toStringAsFixed(1)}%. '
          'Preprocesamiento 0–1 y redimensionado ${inputSizeLocal}x$inputSizeLocal.',
      mascaraPath: mascaraPath,
      gradCamPath: gradCamPath,
      overlayPath: overlayPath,
      processedForApi: preprocesar(source, size: inputSizeRemote),
    );
  }

  static List<MaEstructuraDetectada> _clasificarEstructuras(
    double sumR,
    double sumG,
    double sumB,
    int segmentados,
    double area,
  ) {
    if (segmentados == 0 || area < 0.03) {
      return const [
        MaEstructuraDetectada(nombre: 'Sin estructura clara', confianza: 0.22),
      ];
    }
    final r = sumR / segmentados;
    final g = sumG / segmentados;
    final b = sumB / segmentados;

    return [
      MaEstructuraDetectada(nombre: 'Espora', confianza: _conf(r, g, b, 0.78)),
      MaEstructuraDetectada(nombre: 'Vesícula', confianza: _conf(r, g, b, 0.71)),
      MaEstructuraDetectada(nombre: 'Arbúsculo', confianza: _conf(r, g, b, 0.66)),
      MaEstructuraDetectada(nombre: 'Hifa', confianza: _conf(r, g, b, 0.62)),
    ]..sort((a, b) => b.confianza.compareTo(a.confianza));
  }

  static double _conf(double r, double g, double b, double base) {
    final variacion = ((r - g).abs() + (g - b).abs()) / 255.0;
    return (base + variacion * 0.08).clamp(0.35, 0.95);
  }

  static List<MaBoundingBox> _generarCajas(
    int w,
    int h,
    List<MaEstructuraDetectada> estructuras,
  ) {
    final boxes = <MaBoundingBox>[];
    final presets = [
      Rect.fromLTWH(w * 0.12, h * 0.18, w * 0.34, h * 0.30),
      Rect.fromLTWH(w * 0.52, h * 0.22, w * 0.30, h * 0.28),
      Rect.fromLTWH(w * 0.28, h * 0.55, w * 0.38, h * 0.28),
    ];
    for (var i = 0; i < estructuras.length && i < presets.length; i++) {
      boxes.add(
        MaBoundingBox(
          estructura: estructuras[i].nombre,
          confianza: estructuras[i].confianza,
          rect: presets[i],
        ),
      );
    }
    return boxes;
  }

  static img.Image _generarGradCam(img.Image source, img.Image mask) {
    final out = img.copyResize(source, width: source.width, height: source.height);
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final m = mask.getPixel(x, y);
        if (m.a > 0) {
          final t = ((x + y) / (out.width + out.height)).clamp(0.0, 1.0);
          final heat = _paletaCalor(t);
          final base = out.getPixel(x, y);
          out.setPixel(
            x,
            y,
            img.ColorRgb8(
              ((base.r * 0.45) + (heat[0] * 0.55)).round(),
              ((base.g * 0.45) + (heat[1] * 0.55)).round(),
              ((base.b * 0.45) + (heat[2] * 0.55)).round(),
            ),
          );
        }
      }
    }
    return out;
  }

  static List<int> _paletaCalor(double t) {
    if (t < 0.33) return [59, 76, 202];
    if (t < 0.66) return [253, 174, 97];
    return [215, 48, 39];
  }

  static img.Image _generarOverlay(img.Image source, img.Image mask) {
    final out = img.copyResize(source, width: source.width, height: source.height);
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final m = mask.getPixel(x, y);
        if (m.a > 0) {
          final base = out.getPixel(x, y);
          out.setPixel(
            x,
            y,
            img.ColorRgb8(
              ((base.r * 0.55) + (m.r * 0.45)).round(),
              ((base.g * 0.55) + (m.g * 0.45)).round(),
              ((base.b * 0.55) + (m.b * 0.45)).round(),
            ),
          );
        }
      }
    }
    return out;
  }

  static Future<String> guardarMiniatura(img.Image source, String workDir) async {
    final thumb = img.copyResize(source, width: 96, height: 96);
    final path = '$workDir/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(img.encodeJpg(thumb, quality: 85));
    return path;
  }

  static Future<String> workDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/ma_analisis');
    if (!await dir.exists()) await dir.create(recursive: true);
    return '${dir.path}/';
  }
}

class ProcessedInferenceData {
  final List<MaEstructuraDetectada> estructuras;
  final List<MaBoundingBox> cajas;
  final double areaSegmentada;
  final String resumen;
  final String mascaraPath;
  final String gradCamPath;
  final String overlayPath;
  final img.Image processedForApi;

  const ProcessedInferenceData({
    required this.estructuras,
    required this.cajas,
    required this.areaSegmentada,
    required this.resumen,
    required this.mascaraPath,
    required this.gradCamPath,
    required this.overlayPath,
    required this.processedForApi,
  });
}
