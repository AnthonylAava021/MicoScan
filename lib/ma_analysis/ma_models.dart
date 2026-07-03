import 'dart:ui';

// ─── Enums ────────────────────────────────────────────────────────────────────

/// Modelo a usar en la inferencia remota
enum MaModelo {
  m1,   // Combinado — métricas oficiales (mAP 0.4271)
  m2,   // Solo-LabelMe — visualización orgánica (75 épocas)
  dual, // Corre M1 y M2 simultáneamente
}

extension MaModeloX on MaModelo {
  String get label {
    switch (this) {
      case MaModelo.m1:   return 'Métricas';
      case MaModelo.m2:   return 'Segmentación';
      case MaModelo.dual: return 'Dual';
    }
  }

  String get description {
    switch (this) {
      case MaModelo.m1:   return 'Científico (mAP 0.43)';
      case MaModelo.m2:   return 'Visual (máscaras orgánicas)';
      case MaModelo.dual: return 'M1 métricas + M2 visual';
    }
  }
}

/// Modo de visualización de resultados
enum MaModoViz {
  gtStyle,  // Rectángulos + etiquetas + score
  amfinder, // Grid de tiles con colores
  masks,    // Overlay de segmentación
}

extension MaModoVizX on MaModoViz {
  String get apiValue {
    switch (this) {
      case MaModoViz.gtStyle:  return 'gt_style';
      case MaModoViz.amfinder: return 'amfinder';
      case MaModoViz.masks:    return 'masks';
    }
  }

  String get label {
    switch (this) {
      case MaModoViz.gtStyle:  return 'Segmentar';
      case MaModoViz.amfinder: return 'AMFinder';
      case MaModoViz.masks:    return 'Máscaras';
    }
  }

  String get icon {
    switch (this) {
      case MaModoViz.gtStyle:  return '⬜';
      case MaModoViz.amfinder: return '⊞';
      case MaModoViz.masks:    return '🎭';
    }
  }
}

// ─── Detección individual ──────────────────────────────────────────────────────

/// Una detección del nuevo formato de respuesta del servidor
class MaDeteccion {
  final String clase;       // 'arbuscule' | 'vesicle' | 'hypha'
  final double score;
  final List<double> bbox;  // [x1, y1, x2, y2] en espacio 512×512
  final List<int> color;    // [R, G, B]

  const MaDeteccion({
    required this.clase,
    required this.score,
    required this.bbox,
    required this.color,
  });

  /// Nombre en español
  String get nombreEs {
    switch (clase) {
      case 'arbuscule': return 'Arbúsculo';
      case 'vesicle':   return 'Vesícula';
      case 'hypha':     return 'Hifa';
      default:          return clase;
    }
  }

  Color get colorFlutter => Color.fromARGB(255, color[0], color[1], color[2]);

  Map<String, dynamic> toJson() => {
    'clase': clase,
    'score': score,
    'bbox':  bbox,
    'color': color,
  };

  factory MaDeteccion.fromJson(Map<String, dynamic> json) {
    final bboxRaw  = json['bbox']  as List<dynamic>? ?? [0, 0, 0, 0];
    final colorRaw = json['color'] as List<dynamic>? ?? [180, 180, 180];
    return MaDeteccion(
      clase:  json['clase']  as String? ?? 'arbuscule',
      score:  (json['score'] as num?)?.toDouble() ?? 0,
      bbox:   bboxRaw.map<double>((v) => (v as num).toDouble()).toList(),
      color:  colorRaw.map<int>((v) => (v as num).toInt()).toList(),
    );
  }
}

// ─── Legacy (mantenido para compatibilidad) ───────────────────────────────────

class MaBoundingBox {
  final String estructura;
  final double confianza;
  final Rect rect;

  const MaBoundingBox({
    required this.estructura,
    required this.confianza,
    required this.rect,
  });

  Map<String, dynamic> toJson() => {
    'estructura': estructura,
    'confianza':  confianza,
    'x': rect.left,
    'y': rect.top,
    'w': rect.width,
    'h': rect.height,
  };

  factory MaBoundingBox.fromJson(Map<String, dynamic> json) {
    return MaBoundingBox(
      estructura: json['estructura'] as String? ?? 'estructura',
      confianza:  (json['confianza'] as num?)?.toDouble() ?? 0,
      rect: Rect.fromLTWH(
        (json['x'] as num?)?.toDouble() ?? 0,
        (json['y'] as num?)?.toDouble() ?? 0,
        (json['w'] as num?)?.toDouble() ?? 0,
        (json['h'] as num?)?.toDouble() ?? 0,
      ),
    );
  }
}

class MaEstructuraDetectada {
  final String nombre;
  final double confianza;

  const MaEstructuraDetectada({required this.nombre, required this.confianza});

  Map<String, dynamic> toJson() => {'nombre': nombre, 'confianza': confianza};

  factory MaEstructuraDetectada.fromJson(Map<String, dynamic> json) {
    return MaEstructuraDetectada(
      nombre:    json['nombre']    as String? ?? '—',
      confianza: (json['confianza'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Información de un patch 768×768 analizado por el servidor
class MaPatchInfo {
  final int x, y, w, h;
  final Map<String, int> conteos;
  final int nDets;
  final String? thumbnailB64;

  const MaPatchInfo({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.conteos,
    required this.nDets,
    this.thumbnailB64,
  });

  factory MaPatchInfo.fromJson(Map<String, dynamic> json) {
    final rawConteos = json['conteos'] as Map<String, dynamic>? ?? {};
    return MaPatchInfo(
      x: (json['x'] as num?)?.toInt() ?? 0,
      y: (json['y'] as num?)?.toInt() ?? 0,
      w: (json['w'] as num?)?.toInt() ?? 768,
      h: (json['h'] as num?)?.toInt() ?? 768,
      conteos: rawConteos.map((k, v) => MapEntry(k, (v as num).toInt())),
      nDets:   (json['n_dets'] as num?)?.toInt() ?? 0,
      thumbnailB64: json['thumbnail_b64'] as String?,
    );
  }
}

// ─── Enums de modo de inferencia ──────────────────────────────────────────────

enum MaModoInferencia { local, remoto }

// ─── Resultado principal ───────────────────────────────────────────────────────

class MaResultadoAnalisis {
  final MaModoInferencia modo;
  final String imagenOriginalPath;
  final String? mascaraPath;
  final String? gradCamPath;
  final String? overlayPath;
  final List<MaEstructuraDetectada> estructuras;
  final List<MaBoundingBox> cajas;
  final List<MaPatchInfo> patches;
  final String resumen;
  final double areaSegmentada;
  final int latenciaMs;
  final bool offline;

  // ── Nuevos campos v2 ─────────────────────────────────────────────────────
  final MaModelo modelo;
  final MaModoViz modoViz;
  final bool colonizacion;
  final List<MaDeteccion> detecciones;
  final Map<String, int> counts; // {'arbuscule': N, 'vesicle': N, 'hypha': N}

  const MaResultadoAnalisis({
    required this.modo,
    required this.imagenOriginalPath,
    this.mascaraPath,
    this.gradCamPath,
    this.overlayPath,
    required this.estructuras,
    required this.cajas,
    this.patches = const [],
    required this.resumen,
    required this.areaSegmentada,
    required this.latenciaMs,
    required this.offline,
    // v2 — con defaults para backward-compat
    this.modelo       = MaModelo.m1,
    this.modoViz      = MaModoViz.gtStyle,
    this.colonizacion = false,
    this.detecciones  = const [],
    this.counts       = const {},
  });

  MaEstructuraDetectada? get principal {
    if (estructuras.isEmpty) return null;
    return estructuras.first;
  }

  /// Total de detecciones
  int get totalDetecciones =>
      counts.values.fold(0, (sum, v) => sum + v);

  Map<String, dynamic> toJson() => {
    'modo':             modo.name,
    'imagenOriginalPath': imagenOriginalPath,
    'mascaraPath':      mascaraPath,
    'gradCamPath':      gradCamPath,
    'overlayPath':      overlayPath,
    'estructuras':      estructuras.map((e) => e.toJson()).toList(),
    'cajas':            cajas.map((e) => e.toJson()).toList(),
    'resumen':          resumen,
    'areaSegmentada':   areaSegmentada,
    'latenciaMs':       latenciaMs,
    'offline':          offline,
    'modelo':           modelo.name,
    'modoViz':          modoViz.name,
    'colonizacion':     colonizacion,
    'detecciones':      detecciones.map((d) => d.toJson()).toList(),
    'counts':           counts,
  };

  factory MaResultadoAnalisis.fromJson(Map<String, dynamic> json) {
    final estructurasRaw  = json['estructuras']  as List<dynamic>? ?? [];
    final cajasRaw        = json['cajas']        as List<dynamic>? ?? [];
    final deteccionesRaw  = json['detecciones']  as List<dynamic>? ?? [];
    final countsRaw       = json['counts']       as Map<String, dynamic>? ?? {};

    return MaResultadoAnalisis(
      modo: MaModoInferencia.values.firstWhere(
        (m) => m.name == json['modo'],
        orElse: () => MaModoInferencia.local,
      ),
      imagenOriginalPath: json['imagenOriginalPath'] as String? ?? '',
      mascaraPath:        json['mascaraPath']  as String?,
      gradCamPath:        json['gradCamPath']  as String?,
      overlayPath:        json['overlayPath']  as String?,
      estructuras: estructurasRaw
          .map((e) => MaEstructuraDetectada.fromJson(e as Map<String, dynamic>))
          .toList(),
      cajas: cajasRaw
          .map((e) => MaBoundingBox.fromJson(e as Map<String, dynamic>))
          .toList(),
      resumen:        json['resumen']        as String? ?? '',
      areaSegmentada: (json['areaSegmentada'] as num?)?.toDouble() ?? 0,
      latenciaMs:     (json['latenciaMs']    as num?)?.toInt()    ?? 0,
      offline:        json['offline']        as bool? ?? true,
      modelo: MaModelo.values.firstWhere(
        (m) => m.name == json['modelo'],
        orElse: () => MaModelo.m1,
      ),
      modoViz: MaModoViz.values.firstWhere(
        (m) => m.name == json['modoViz'],
        orElse: () => MaModoViz.gtStyle,
      ),
      colonizacion: json['colonizacion'] as bool? ?? false,
      detecciones: deteccionesRaw
          .map((d) => MaDeteccion.fromJson(d as Map<String, dynamic>))
          .toList(),
      counts: countsRaw.map((k, v) => MapEntry(k, (v as num).toInt())),
    );
  }
}

// ─── Historial ────────────────────────────────────────────────────────────────

class MaHistorialItem {
  final String id;
  final DateTime fecha;
  final String imagenPath;
  final String thumbnailPath;
  final MaResultadoAnalisis resultado;

  const MaHistorialItem({
    required this.id,
    required this.fecha,
    required this.imagenPath,
    required this.thumbnailPath,
    required this.resultado,
  });

  Map<String, dynamic> toJson() => {
    'id':             id,
    'fecha':          fecha.toIso8601String(),
    'imagenPath':     imagenPath,
    'thumbnailPath':  thumbnailPath,
    'resultado':      resultado.toJson(),
  };

  factory MaHistorialItem.fromJson(Map<String, dynamic> json) {
    return MaHistorialItem(
      id:            json['id']            as String? ?? '',
      fecha:         DateTime.tryParse(json['fecha'] as String? ?? '') ?? DateTime.now(),
      imagenPath:    json['imagenPath']    as String? ?? '',
      thumbnailPath: json['thumbnailPath'] as String? ?? '',
      resultado:     MaResultadoAnalisis.fromJson(
                       json['resultado'] as Map<String, dynamic>),
    );
  }
}
