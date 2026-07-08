import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

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
    final cajas = await AmfLocalClassifier.instance.detectObjects(source, threshold: umbralBrillo);

    // Conteo de estructuras detectadas localmente
    int cArbusculos = 0;
    int cVesiculas = 0;
    int cHifas = 0;

    for (final d in cajas) {
      if (d.estructura == 'arbuscule') cArbusculos++;
      if (d.estructura == 'vesicle') cVesiculas++;
      if (d.estructura == 'hypha') cHifas++;
    }

    final counts = {
      'arbuscule': cArbusculos,
      'vesicle':   cVesiculas,
      'hypha':     cHifas,
    };

    final totalDetecciones = cArbusculos + cVesiculas + cHifas;
    final colonizacion = totalDetecciones > 0;

    final estructurasOnnx = _countsToEstructuras(counts);

    final data = await MaImageProcessor.analizarEdge(
      source: source,
      umbralBrillo: umbralBrillo,
      workDir: workDir,
    );

    final visibles = <String>[];
    if (cArbusculos > 0) visibles.add('Arbúsculos ($cArbusculos)');
    if (cVesiculas > 0) visibles.add('Vesículas ($cVesiculas)');
    if (cHifas > 0) visibles.add('Hifas ($cHifas)');

    final String textoColonizacion = colonizacion 
        ? 'SÍ (Colonización Micorrízica Detectada)' 
        : 'NO (No se detectó colonización)';

    final String textoEstructuras = visibles.isNotEmpty 
        ? 'Estructuras identificadas: ${visibles.join(", ")}.' 
        : 'No se identificaron estructuras fúngicas.';

    final resumenOnnx =
        'Análisis Local (100% Offline):\n'
        '• Colonización: $textoColonizacion\n'
        '• $textoEstructuras\n'
        '• Total estructuras: $totalDetecciones unidades\n'
        '• Raíz Segmentada (Área): ${(data.areaSegmentada * 100).toStringAsFixed(1)}%';

    return MaResultadoAnalisis(
      modo:              MaModoInferencia.local,
      imagenOriginalPath: imagePath,
      mascaraPath:       data.mascaraPath,
      gradCamPath:       data.gradCamPath,
      overlayPath:       data.overlayPath,
      estructuras:       estructurasOnnx,
      cajas:             cajas,
      resumen:           resumenOnnx,
      areaSegmentada:    data.areaSegmentada,
      latenciaMs:        DateTime.now().difference(inicio).inMilliseconds,
      offline:           true,
      modelo:            MaModelo.m1,
      modoViz:           MaModoViz.gtStyle,
      colonizacion:      colonizacion,
      counts:            counts,
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
    http.StreamedResponse streamed;
    try {
      streamed = await client.send(request).timeout(
        const Duration(seconds: _kTimeoutSec),
        onTimeout: () => throw Exception('Tiempo agotado. Intenta con una imagen más pequeña.'),
      );
    } catch (e) {
      throw Exception('No se pudo establecer conexión con el servidor. Verifica que tu teléfono esté conectado al mismo WiFi que la computadora y que el servidor de IA esté encendido.');
    }

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
    http.StreamedResponse streamed;
    try {
      streamed = await client.send(request).timeout(
        const Duration(seconds: _kTimeoutSec),
        onTimeout: () => throw Exception('Tiempo agotado. Intenta con una imagen más pequeña.'),
      );
    } catch (e) {
      throw Exception('No se pudo establecer conexión con el servidor. Verifica que tu teléfono esté conectado al mismo WiFi que la computadora y que el servidor de IA esté encendido.');
    }

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

  /// Validación de microscopio para evitar screenshots o imágenes inválidas
  static bool _validarImagenMicroscopio(img.Image image) {
    final totalPixeles = image.width * image.height;
    if (totalPixeles == 0) return false;

    int pureBlack = 0;
    int pureWhite = 0;
    int darkPixels = 0;

    // Muestrear píxeles de forma rápida para no ralentizar el celular
    final int paso = (totalPixeles ~/ 2000).clamp(1, 100);
    int contados = 0;

    for (int y = 0; y < image.height; y += paso) {
      for (int x = 0; x < image.width; x += paso) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // 1. Verificar negros o grises muy oscuros (screenshots modo oscuro)
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        if (lum < 15) {
          darkPixels++;
        }

        // 2. Verificar negros y blancos digitales puros (UI digital/texto)
        if (r == 0 && g == 0 && b == 0) {
          pureBlack++;
        } else if (r == 255 && g == 255 && b == 255) {
          pureWhite++;
        }
        contados++;
      }
    }

    if (contados == 0) return false;

    // Si es demasiado oscura (modo oscuro)
    if (darkPixels / contados > 0.40) {
      return false;
    }

    // Si tiene demasiados colores digitales perfectos (UI/Textos)
    if ((pureBlack + pureWhite) / contados > 0.12) {
      return false;
    }

    return true;
  }
}
