import 'dart:ui';

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
        'confianza': confianza,
        'x': rect.left,
        'y': rect.top,
        'w': rect.width,
        'h': rect.height,
      };

  factory MaBoundingBox.fromJson(Map<String, dynamic> json) {
    return MaBoundingBox(
      estructura: json['estructura'] as String? ?? 'estructura',
      confianza: (json['confianza'] as num?)?.toDouble() ?? 0,
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
      nombre: json['nombre'] as String? ?? '—',
      confianza: (json['confianza'] as num?)?.toDouble() ?? 0,
    );
  }
}

enum MaModoInferencia { local, remoto }

class MaResultadoAnalisis {
  final MaModoInferencia modo;
  final String imagenOriginalPath;
  final String? mascaraPath;
  final String? gradCamPath;
  final String? overlayPath;
  final List<MaEstructuraDetectada> estructuras;
  final List<MaBoundingBox> cajas;
  final String resumen;
  final double areaSegmentada;
  final int latenciaMs;
  final bool offline;

  const MaResultadoAnalisis({
    required this.modo,
    required this.imagenOriginalPath,
    this.mascaraPath,
    this.gradCamPath,
    this.overlayPath,
    required this.estructuras,
    required this.cajas,
    required this.resumen,
    required this.areaSegmentada,
    required this.latenciaMs,
    required this.offline,
  });

  MaEstructuraDetectada? get principal {
    if (estructuras.isEmpty) return null;
    return estructuras.reduce((a, b) => a.confianza >= b.confianza ? a : b);
  }

  Map<String, dynamic> toJson() => {
        'modo': modo.name,
        'imagenOriginalPath': imagenOriginalPath,
        'mascaraPath': mascaraPath,
        'gradCamPath': gradCamPath,
        'overlayPath': overlayPath,
        'estructuras': estructuras.map((e) => e.toJson()).toList(),
        'cajas': cajas.map((e) => e.toJson()).toList(),
        'resumen': resumen,
        'areaSegmentada': areaSegmentada,
        'latenciaMs': latenciaMs,
        'offline': offline,
      };

  factory MaResultadoAnalisis.fromJson(Map<String, dynamic> json) {
    final estructurasRaw = json['estructuras'] as List<dynamic>? ?? [];
    final cajasRaw = json['cajas'] as List<dynamic>? ?? [];
    return MaResultadoAnalisis(
      modo: MaModoInferencia.values.firstWhere(
        (m) => m.name == json['modo'],
        orElse: () => MaModoInferencia.local,
      ),
      imagenOriginalPath: json['imagenOriginalPath'] as String? ?? '',
      mascaraPath: json['mascaraPath'] as String?,
      gradCamPath: json['gradCamPath'] as String?,
      overlayPath: json['overlayPath'] as String?,
      estructuras: estructurasRaw
          .map((e) => MaEstructuraDetectada.fromJson(e as Map<String, dynamic>))
          .toList(),
      cajas: cajasRaw
          .map((e) => MaBoundingBox.fromJson(e as Map<String, dynamic>))
          .toList(),
      resumen: json['resumen'] as String? ?? '',
      areaSegmentada: (json['areaSegmentada'] as num?)?.toDouble() ?? 0,
      latenciaMs: json['latenciaMs'] as int? ?? 0,
      offline: json['offline'] as bool? ?? true,
    );
  }
}

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
        'id': id,
        'fecha': fecha.toIso8601String(),
        'imagenPath': imagenPath,
        'thumbnailPath': thumbnailPath,
        'resultado': resultado.toJson(),
      };

  factory MaHistorialItem.fromJson(Map<String, dynamic> json) {
    return MaHistorialItem(
      id: json['id'] as String? ?? '',
      fecha: DateTime.tryParse(json['fecha'] as String? ?? '') ?? DateTime.now(),
      imagenPath: json['imagenPath'] as String? ?? '',
      thumbnailPath: json['thumbnailPath'] as String? ?? '',
      resultado: MaResultadoAnalisis.fromJson(json['resultado'] as Map<String, dynamic>),
    );
  }
}
