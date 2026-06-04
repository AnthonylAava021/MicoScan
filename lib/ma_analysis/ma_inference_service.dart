import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'ma_image_processor.dart';
import 'ma_models.dart';

/// URL del backend FastAPI/Flask. En emulador Android: http://10.0.2.2:8000
const String kMaInferenceApiUrl = String.fromEnvironment(
  'MA_API_URL',
  defaultValue: 'http://10.0.2.2:8000/api/infer',
);

class MaInferenceService {
  static const _timeoutRemoto = Duration(seconds: 30);

  static Future<bool> hayConectividad() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// RF-03: inferencia local offline (edge). Integrar `assets/models/ma_mask_rcnn_int8.tflite`
  /// con `tflite_flutter` cuando el modelo cuantizado esté disponible.
  static Future<MaResultadoAnalisis> inferirLocal({
    required String imagePath,
    required double umbralBrillo,
  }) async {
    final inicio = DateTime.now();
    final source = await MaImageProcessor.validarYCargar(imagePath);
    final workDir = await MaImageProcessor.workDirectory();
    final data = await MaImageProcessor.analizarEdge(
      source: source,
      umbralBrillo: umbralBrillo,
      workDir: workDir,
    );

    return MaResultadoAnalisis(
      modo: MaModoInferencia.local,
      imagenOriginalPath: imagePath,
      mascaraPath: data.mascaraPath,
      gradCamPath: data.gradCamPath,
      overlayPath: data.overlayPath,
      estructuras: data.estructuras,
      cajas: data.cajas,
      resumen: data.resumen,
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
    final source = await MaImageProcessor.validarYCargar(imagePath);
    final processed = MaImageProcessor.preprocesar(
      source,
      size: MaImageProcessor.inputSizeRemote,
    );
    final pngBytes = img.encodePng(processed);
    final uri = Uri.parse(apiUrl ?? kMaInferenceApiUrl);

    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          pngBytes,
          filename: 'muestra.png',
        ),
      );

    final streamed = await request.send().timeout(_timeoutRemoto);
    final response = await http.Response.fromStream(streamed).timeout(_timeoutRemoto);

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
      resumen: json['resumen'] as String? ?? 'Resultado remoto recibido correctamente.',
      areaSegmentada: (json['area_segmentada'] as num?)?.toDouble() ?? 0,
      latenciaMs: latenciaMs,
      offline: false,
    );
  }
}
