import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import 'amf_local_classifier.dart';
import 'dev_http_client.dart';
import 'ma_api_config.dart';
import 'ma_image_processor.dart';
import 'ma_models.dart';

class MaInferenceService {
  static const int _kTimeoutSec = 180;

  static Future<bool> hayConectividad() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  // ─── Headers comunes ──────────────────────────────────────────────────────
  static Map<String, String> get _headers => {
    'ngrok-skip-browser-warning': 'true',
    'User-Agent': 'MicoScan-App/1.0',
    'Accept':     'application/json',
  };

  // ─── Inferencia local (ONNX offline) ─────────────────────────────────────

  /// RF-03: inferencia local offline con modelo ONNX (ResNet-50 backbone).
  static Future<MaResultadoAnalisis> inferirLocal({
    required String imagePath,
    required double umbralBrillo,
  }) async {
    final inicio = DateTime.now();
    final source  = await MaImageProcessor.validarYCargar(imagePath);
    final workDir = await MaImageProcessor.workDirectory();

    await AmfLocalClassifier.instance.load();
    final probs = await AmfLocalClassifier.instance.classifyImage(source);

    final estructurasOnnx = [
      MaEstructuraDetectada(nombre: 'Arbúsculo', confianza: probs['arbuscule']!),
      MaEstructuraDetectada(nombre: 'Vesícula',  confianza: probs['vesicle']!),
      MaEstructuraDetectada(nombre: 'Hifa',      confianza: probs['hypha']!),
    ]..sort((a, b) => b.confianza.compareTo(a.confianza));

    final data = await MaImageProcessor.analizarEdge(
      source: source,
      umbralBrillo: umbralBrillo,
      workDir: workDir,
    );

    final resumenOnnx =
        'Clasificación offline (ONNX ResNet-50). '
        'Arbúsculo: ${(probs["arbuscule"]! * 100).toStringAsFixed(1)}% | '
        'Vesícula: ${(probs["vesicle"]! * 100).toStringAsFixed(1)}% | '
        'Hifa: ${(probs["hypha"]! * 100).toStringAsFixed(1)}%. '
        'Área segmentada: ${(data.areaSegmentada * 100).toStringAsFixed(1)}%.';

    // Determinar colonización: si alguna prob > 25 %
    final colonizacion = probs.values.any((p) => p > 0.25);

    return MaResultadoAnalisis(
      modo:              MaModoInferencia.local,
      imagenOriginalPath: imagePath,
      mascaraPath:       data.mascaraPath,
      gradCamPath:       data.gradCamPath,
      overlayPath:       data.overlayPath,
      estructuras:       estructurasOnnx,
      cajas:             data.cajas,
      resumen:           resumenOnnx,
      areaSegmentada:    data.areaSegmentada,
      latenciaMs:        DateTime.now().difference(inicio).inMilliseconds,
      offline:           true,
      modelo:            MaModelo.m1,
      modoViz:           MaModoViz.gtStyle,
      colonizacion:      colonizacion,
      counts: {
        'arbuscule': (probs['arbuscule']! > 0.25) ? 1 : 0,
        'vesicle':   (probs['vesicle']!   > 0.25) ? 1 : 0,
        'hypha':     (probs['hypha']!     > 0.25) ? 1 : 0,
      },
    );
  }

  // ─── Inferencia remota (/api/infer) ───────────────────────────────────────

  /// RF-04: inferencia remota con modelo M1 o M2.
  static Future<MaResultadoAnalisis> inferirRemoto({
    required String imagePath,
    String?   apiBase,
    MaModelo  modelo  = MaModelo.m1,
    MaModoViz modoViz = MaModoViz.gtStyle,
  }) async {
    if (!await hayConectividad()) {
      throw Exception('Sin conexión a internet. Use inferencia local (RF-03).');
    }

    final inicio    = DateTime.now();
    final rawBytes  = await File(imagePath).readAsBytes();
    final base      = apiBase ?? MaApiConfig.baseUrl;
    final uri = Uri.parse('$base/api/infer').replace(queryParameters: {
      'modelo': modelo.label,         // 'M1' | 'M2'
      'modo':   modoViz.apiValue,     // 'gt_style' | 'amfinder' | 'masks'
    });

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers)
      ..files.add(http.MultipartFile.fromBytes(
        'image',
        rawBytes,
        filename: 'muestra.jpg',
      ));

    final client   = createDevHttpClient();
    final streamed = await client.send(request).timeout(
      const Duration(seconds: _kTimeoutSec),
      onTimeout: () => throw Exception('Tiempo agotado. Intenta con una imagen más pequeña.'),
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
    return _parsearRespuesta(
      jsonMap,
      imagePath:   imagePath,
      workDir:     workDir,
      latenciaMs:  DateTime.now().difference(inicio).inMilliseconds,
      modelo:      modelo,
      modoViz:     modoViz,
    );
  }

  // ─── Inferencia dual (/api/infer_dual) ───────────────────────────────────

  /// Corre M1 y M2 simultáneamente. Retorna resultado con:
  ///   - overlay visual de M2 (máscaras orgánicas)
  ///   - métricas y detecciones de M1
  ///   - colonizacion del servidor
  static Future<MaResultadoAnalisis> inferirDual({
    required String imagePath,
    String?   apiBase,
    MaModoViz modoViz = MaModoViz.gtStyle,
  }) async {
    if (!await hayConectividad()) {
      throw Exception('Sin conexión a internet. Use inferencia local (RF-03).');
    }

    final inicio   = DateTime.now();
    final rawBytes = await File(imagePath).readAsBytes();
    final base     = apiBase ?? MaApiConfig.baseUrl;
    final uri = Uri.parse('$base/api/infer_dual').replace(queryParameters: {
      'modo': modoViz.apiValue,
    });

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers)
      ..files.add(http.MultipartFile.fromBytes(
        'image',
          rawBytes,
        filename: 'muestra.jpg',
      ));

    final client   = createDevHttpClient();
    final streamed = await client.send(request).timeout(
      const Duration(seconds: _kTimeoutSec),
      onTimeout: () => throw Exception('Tiempo agotado. Intenta con una imagen más pequeña.'),
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
    final latenciaMs = DateTime.now().difference(inicio).inMilliseconds;

    // En dual: resultado visual = M2, métricas = M1
    final m1 = jsonMap['M1'] as Map<String, dynamic>? ?? {};
    final m2 = jsonMap['M2'] as Map<String, dynamic>? ?? {};

    // Detecciones de M1 para reportar métricas
    final deteccionesRaw = m1['detecciones'] as List<dynamic>? ?? [];
    final detecciones = deteccionesRaw
        .map((d) => MaDeteccion.fromJson(d as Map<String, dynamic>))
        .toList();

    // Counts de M1
    final countsM1 = (m1['counts'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, (v as num).toInt()));

    // Estructuras de M1
    final estructuras = _countsToEstructuras(countsM1);

    // Overlay visual de M2 (o M1 si M2 no lo tiene)
    final overlayB64 = jsonMap['resultado'] as String?
        ?? m2['resultado']   as String?
        ?? m1['resultado']   as String?;
    final originalB64 = jsonMap['original'] as String?;

    String? overlayPath;
    String? originalPath;
    final stamp = DateTime.now().millisecondsSinceEpoch;

    if (overlayB64 != null) {
      overlayPath = '$workDir/overlay_dual_$stamp.jpg';
      await File(overlayPath).writeAsBytes(_decodeBase64Img(overlayB64));
    }
    if (originalB64 != null) {
      originalPath = '$workDir/original_dual_$stamp.jpg';
      await File(originalPath).writeAsBytes(_decodeBase64Img(originalB64));
    }

    final totalM1 = (m1['total'] as num?)?.toInt() ?? 0;
    final latM1   = (m1['latencia_ms'] as num?)?.toInt() ?? 0;
    final latM2   = (m2['latencia_ms'] as num?)?.toInt() ?? 0;

    return MaResultadoAnalisis(
      modo:              MaModoInferencia.remoto,
      imagenOriginalPath: originalPath ?? imagePath,
      overlayPath:       overlayPath,
      estructuras:       estructuras,
      cajas:             [],
      resumen: 'Dual M1+M2 | M1: $totalM1 det (${latM1}ms) | M2: ${latM2}ms',
      areaSegmentada:    0,
      latenciaMs:        latenciaMs,
      offline:           false,
      modelo:            MaModelo.dual,
      modoViz:           modoViz,
      colonizacion:      jsonMap['colonizacion'] as bool? ?? (totalM1 > 0),
      detecciones:       detecciones,
      counts:            countsM1,
    );
  }

  // ─── Parser respuesta única ───────────────────────────────────────────────

  static Future<MaResultadoAnalisis> _parsearRespuesta(
    Map<String, dynamic> json, {
    required String    imagePath,
    required String    workDir,
    required int       latenciaMs,
    required MaModelo  modelo,
    required MaModoViz modoViz,
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // ── Imágenes base64 ──
    String? overlayPath;
    String? mascaraPath;
    String? gradCamPath;
    String? originalPath;

    // Nuevo formato: campo "resultado" para el overlay
    final resultadoB64 = json['resultado'] as String?
        ?? json['overlay_base64']   as String?;
    final originalB64  = json['original']  as String?;
    final mascaraB64   = json['mascara_base64']  as String?;
    final gradCamB64   = json['grad_cam_base64'] as String?;

    if (resultadoB64 != null) {
      overlayPath = '$workDir/overlay_remote_$stamp.jpg';
      await File(overlayPath).writeAsBytes(_decodeBase64Img(resultadoB64));
    }
    if (originalB64 != null) {
      originalPath = '$workDir/original_remote_$stamp.jpg';
      await File(originalPath).writeAsBytes(_decodeBase64Img(originalB64));
    }
    if (mascaraB64 != null) {
      mascaraPath = '$workDir/mask_remote_$stamp.png';
      await File(mascaraPath).writeAsBytes(_decodeBase64Img(mascaraB64));
    }
    if (gradCamB64 != null) {
      gradCamPath = '$workDir/grad_remote_$stamp.png';
      await File(gradCamPath).writeAsBytes(_decodeBase64Img(gradCamB64));
    }

    // ── Detecciones (nuevo formato) ──
    final deteccionesRaw = json['detecciones'] as List<dynamic>? ?? [];
    final detecciones = deteccionesRaw
        .map((d) => MaDeteccion.fromJson(d as Map<String, dynamic>))
        .toList();

    // ── Counts ──
    final countsRaw = json['counts'] as Map<String, dynamic>? ?? {};
    final counts    = countsRaw.map((k, v) => MapEntry(k, (v as num).toInt()));

    // ── Estructuras (nuevo formato usa counts / detecciones, no "estructuras") ──
    List<MaEstructuraDetectada> estructuras;
    final estructurasRaw = json['estructuras'] as List<dynamic>?;
    if (estructurasRaw != null && estructurasRaw.isNotEmpty) {
      estructuras = estructurasRaw
          .map((e) => MaEstructuraDetectada.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      estructuras = _countsToEstructuras(counts);
    }

    // ── Cajas legacy ──
    final cajasRaw = json['cajas'] as List<dynamic>?
        ?? json['bounding_boxes'] as List<dynamic>?
        ?? [];
    final cajas = cajasRaw
        .map((e) => MaBoundingBox.fromJson(e as Map<String, dynamic>))
        .toList();

    // ── Patches ──
    final patchesRaw = json['patches'] as List<dynamic>? ?? [];
    final patches    = patchesRaw
        .map((e) => MaPatchInfo.fromJson(e as Map<String, dynamic>))
        .toList();

    final total        = (json['total']         as num?)?.toInt() ?? detecciones.length;
    final latenciaServ = (json['latencia_ms']   as num?)?.toInt() ?? latenciaMs;
    final colonizacion = json['colonizacion']   as bool? ?? (total > 0);
    final areaSegm     = (json['area_segmentada'] as num?)?.toDouble() ?? 0;

    final resumen = json['resumen'] as String?
        ?? _buildResumen(json['modelo'] as String? ?? modelo.label,
                         counts, total, latenciaServ);

    return MaResultadoAnalisis(
      modo:              MaModoInferencia.remoto,
      imagenOriginalPath: originalPath ?? imagePath,
      mascaraPath:       mascaraPath,
      gradCamPath:       gradCamPath,
      overlayPath:       overlayPath,
      estructuras:       estructuras,
      cajas:             cajas,
      patches:           patches,
      resumen:           resumen,
      areaSegmentada:    areaSegm,
      latenciaMs:        latenciaMs,
      offline:           false,
      modelo:            modelo,
      modoViz:           modoViz,
      colonizacion:      colonizacion,
      detecciones:       detecciones,
      counts:            counts,
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static List<MaEstructuraDetectada> _countsToEstructuras(Map<String, int> counts) {
    const nombres = {
      'arbuscule': 'Arbúsculo',
      'vesicle':   'Vesícula',
      'hypha':     'Hifa',
    };
    final total = counts.values.fold(0, (s, v) => s + v);
    return counts.entries
        .where((e) => e.value > 0)
        .map((e) => MaEstructuraDetectada(
              nombre:    nombres[e.key] ?? e.key,
              confianza: total > 0 ? e.value / total : 0,
            ))
        .toList()
      ..sort((a, b) => b.confianza.compareTo(a.confianza));
  }

  static String _buildResumen(
    String modelo,
    Map<String, int> counts,
    int total,
    int latenciaMs,
  ) {
    final a = counts['arbuscule'] ?? 0;
    final v = counts['vesicle']   ?? 0;
    final h = counts['hypha']     ?? 0;
    return '$modelo | $total det. | '
        'Arbúsculos: $a | Vesículas: $v | Hifas: $h | ${latenciaMs}ms';
  }

  static List<int> _decodeBase64Img(String b64) {
    // El servidor puede enviar data-URI o base64 puro
    final clean = b64.contains(',') ? b64.split(',').last : b64;
    return base64Decode(clean);
  }
}
