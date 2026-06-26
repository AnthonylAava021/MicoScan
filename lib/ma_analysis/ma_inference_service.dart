import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import 'amf_local_classifier.dart';
import 'dev_http_client.dart';
import 'ma_image_processor.dart';
import 'ma_models.dart';


/// URL del backend FastAPI con Mask R-CNN completo.
/// El servidor corre en el PC con: python micoscan_server.py
const String kMaInferenceApiUrl = String.fromEnvironment(
  'MA_API_URL',
  defaultValue: 'https://dana-epa-exhibition-slight.trycloudflare.com/api/infer',
);

class MaInferenceService {
  // Imagenes grandes con patches 768x768 tardan ~30-60s en GPU
  static const int _kTimeoutSec = 180;

  static Future<bool> hayConectividad() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// RF-03: inferencia local offline con modelo ONNX (ResNet-50 backbone).
  /// Clasifica presencia de arbúsculo, vesícula e hifa mediante `AmfLocalClassifier`.
  /// Las visualizaciones (máscara, gradcam, overlay) se generan por heurística
  /// local mientras el Mask R-CNN completo no esté disponible en edge.
  static Future<MaResultadoAnalisis> inferirLocal({
    required String imagePath,
    required double umbralBrillo,
  }) async {
    final inicio = DateTime.now();
    final source = await MaImageProcessor.validarYCargar(imagePath);
    final workDir = await MaImageProcessor.workDirectory();

    // ── 1. Clasificación real con el modelo ONNX ────────────────────────────
    await AmfLocalClassifier.instance.load();
    final probs = await AmfLocalClassifier.instance.classifyImage(source);

    // Mapear a MaEstructuraDetectada (excluir background)
    final estructurasOnnx = [
      MaEstructuraDetectada(nombre: 'Arbúsculo', confianza: probs['arbuscule']!),
      MaEstructuraDetectada(nombre: 'Vesícula',  confianza: probs['vesicle']!),
      MaEstructuraDetectada(nombre: 'Hifa',      confianza: probs['hypha']!),
    ]..sort((a, b) => b.confianza.compareTo(a.confianza));

    // ── 2. Visualizaciones locales (heurística de brillo) ───────────────────
    final data = await MaImageProcessor.analizarEdge(
      source: source,
      umbralBrillo: umbralBrillo,
      workDir: workDir,
    );

    // ── 3. Resumen enriquecido con probabilidades reales ────────────────────
    final resumenOnnx =
        'Clasificación offline (ONNX ResNet-50). '
        'Arbúsculo: ${(probs["arbuscule"]! * 100).toStringAsFixed(1)}% | '
        'Vesícula: ${(probs["vesicle"]! * 100).toStringAsFixed(1)}% | '
        'Hifa: ${(probs["hypha"]! * 100).toStringAsFixed(1)}%. '
        'Área segmentada: ${(data.areaSegmentada * 100).toStringAsFixed(1)}%.';

    return MaResultadoAnalisis(
      modo: MaModoInferencia.local,
      imagenOriginalPath: imagePath,
      mascaraPath: data.mascaraPath,
      gradCamPath: data.gradCamPath,
      overlayPath: data.overlayPath,
      estructuras: estructurasOnnx,
      cajas: data.cajas,
      resumen: resumenOnnx,
      areaSegmentada: data.areaSegmentada,
      latenciaMs: DateTime.now().difference(inicio).inMilliseconds,
      offline: true,
    );
  }

  /// RF-04: inferencia remota vía API REST.
  static Future<MaResultadoAnalisis> inferirRemoto({
    required String imagePath,
    String? apiUrl,
  }) async {
    if (!await hayConectividad()) {
      throw Exception('Sin conexión a internet. Use inferencia local (RF-03).');
    }

    final inicio = DateTime.now();
    // Para modo API enviamos la imagen original sin redimensionar.
    // El servidor hace sliding window de patches 512x512 internamente.
    final rawBytes = await File(imagePath).readAsBytes();
    final uri = Uri.parse(apiUrl ?? kMaInferenceApiUrl);

    final request = http.MultipartRequest('POST', uri)
      ..headers['ngrok-skip-browser-warning'] = 'true'
        ..headers['User-Agent'] = 'MicoScan-App/1.0'
        ..headers['Accept'] = 'application/json'
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          rawBytes,
          filename: 'muestra.jpg',
        ),
      );

    final client = createDevHttpClient();
    final streamed = await client.send(request).timeout(
      const Duration(seconds: 180),
      onTimeout: () => throw Exception('Tiempo agotado. La imagen es muy grande o el servidor está ocupado. Intenta con una imagen más pequeña.'),
    );
    final response = await http.Response.fromStream(streamed).timeout(
      const Duration(seconds: _kTimeoutSec),
      onTimeout: () => throw Exception('Servidor no respondió a tiempo.'),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Error del servidor (${response.statusCode}): ${response.body}');
    }

    final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
    final workDir = await MaImageProcessor.workDirectory();
    return _parsearRespuestaRemota(
      jsonMap,
      imagePath: imagePath,
      workDir: workDir,
      latenciaMs: DateTime.now().difference(inicio).inMilliseconds,
    );
  }

  static Future<MaResultadoAnalisis> _parsearRespuestaRemota(
    Map<String, dynamic> json, {
    required String imagePath,
    required String workDir,
    required int latenciaMs,
  }) async {
    final estructurasRaw = json['estructuras'] as List<dynamic>? ?? [];
    final estructuras = estructurasRaw
        .map((e) => MaEstructuraDetectada.fromJson(e as Map<String, dynamic>))
        .toList();

    final cajasRaw = json['cajas'] as List<dynamic>? ?? json['bounding_boxes'] as List<dynamic>? ?? [];
    final cajas = cajasRaw
        .map((e) => MaBoundingBox.fromJson(e as Map<String, dynamic>))
        .toList();

    // Patches info del servidor (visualización de cuadrícula)
    final patchesRaw = json['patches'] as List<dynamic>? ?? [];
    final patches = patchesRaw
        .map((e) => MaPatchInfo.fromJson(e as Map<String, dynamic>))
        .toList();

    String? mascaraPath;
    String? gradCamPath;
    String? overlayPath;

    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (json['mascara_base64'] != null) {
      mascaraPath = '$workDir/mask_remote_$stamp.png';
      await File(mascaraPath).writeAsBytes(base64Decode(json['mascara_base64'] as String));
    }
    if (json['grad_cam_base64'] != null) {
      gradCamPath = '$workDir/grad_remote_$stamp.png';
      await File(gradCamPath).writeAsBytes(base64Decode(json['grad_cam_base64'] as String));
    }
    if (json['overlay_base64'] != null) {
      overlayPath = '$workDir/overlay_remote_$stamp.png';
      await File(overlayPath).writeAsBytes(base64Decode(json['overlay_base64'] as String));
    }

    return MaResultadoAnalisis(
      modo: MaModoInferencia.remoto,
      imagenOriginalPath: imagePath,
      mascaraPath: mascaraPath,
      gradCamPath: gradCamPath,
      overlayPath: overlayPath,
      estructuras: estructuras,
      cajas: cajas,
      patches: patches,
      resumen: json['resumen'] as String? ?? 'Resultado remoto recibido correctamente.',
      areaSegmentada: (json['area_segmentada'] as num?)?.toDouble() ?? 0,
      latenciaMs: latenciaMs,
      offline: false,
    );
  }
}
