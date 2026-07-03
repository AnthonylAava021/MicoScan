import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'dev_http_client.dart';
import 'ma_inference_service.dart';
import 'ma_pipeline_store.dart';

const String kPreprocessApiUrl = String.fromEnvironment(
  'MA_API_URL',
  defaultValue: 'https://washer-angela-flights-based.trycloudflare.com/api/preprocess',
);

class PreprocesarPipelineScreen extends StatefulWidget {
  const PreprocesarPipelineScreen({super.key});

  @override
  State<PreprocesarPipelineScreen> createState() =>
      _PreprocesarPipelineScreenState();
}

class _PreprocesarPipelineScreenState
    extends State<PreprocesarPipelineScreen> {
  final _picker = ImagePicker();
  String? _imagePath;
  bool _cargando = false;
  String? _error;
  Map<String, dynamic>? _resultado;

  bool _desdeAnalisis = false;

  @override
  void initState() {
    super.initState();
    _cargarDesdeStore();
  }

  /// Carga automáticamente el resultado del último análisis
  void _cargarDesdeStore() {
    final store = MaPipelineStore.instance;
    if (store.imagePath == null) return; // No hay análisis previo

    _desdeAnalisis = true;
    _imagePath     = store.imagePath;

    if (store.preprocessResult != null) {
      // Ya tiene resultado — mostrar inmediatamente
      _resultado = store.preprocessResult;
      _cargando  = false;
      _error     = null;
    } else if (store.loading) {
      // Aún procesando en background — esperar
      _cargando = true;
      _esperarStore();
    } else if (store.error != null) {
      _error    = store.error;
      _cargando = false;
    }
  }

  /// Sondea el store cada 500ms hasta que termine el background task
  Future<void> _esperarStore() async {
    final store = MaPipelineStore.instance;
    while (store.loading && mounted) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (!mounted) return;
    setState(() {
      _resultado = store.preprocessResult;
      _error     = store.error;
      _cargando  = false;
    });
  }

  Future<void> _elegirImagen(ImageSource src) async {
    final f = await _picker.pickImage(source: src, imageQuality: 95);
    if (f == null) return;
    setState(() {
      _imagePath     = f.path;
      _resultado     = null;
      _error         = null;
      _desdeAnalisis = false;
    });
    await _enviarPreprocesamiento(f.path);
  }

  Future<void> _enviarPreprocesamiento(String path) async {
    if (!await MaInferenceService.hayConectividad()) {
      setState(() => _error = 'Sin conexión. Conecta el WiFi.');
      return;
    }
    setState(() { _cargando = true; _error = null; });
    try {
      final bytes = await File(path).readAsBytes();
      final uri = Uri.parse(kPreprocessApiUrl);
      final req = http.MultipartRequest('POST', uri)
        ..headers['ngrok-skip-browser-warning'] = 'true'
        ..headers['User-Agent'] = 'MicoScan-App/1.0'
        ..headers['Accept'] = 'application/json'
        ..files.add(http.MultipartFile.fromBytes('image', bytes, filename: 'img.jpg'));
      final client = createDevHttpClient();
      final streamed = await client.send(req).timeout(const Duration(seconds: 60));
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode != 200) {
        throw Exception('Error ${resp.statusCode}: ${resp.body}');
      }
      setState(() => _resultado = jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FC),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 120,
            backgroundColor: const Color(0xFF1A3A5C),
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Pipeline de Preprocesamiento',
                style: TextStyle(fontSize: 14, color: Colors.white),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A3A5C), Color(0xFF0D6EFD)],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.auto_fix_high_rounded,
                      size: 48, color: Colors.white24),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_desdeAnalisis && _imagePath != null)
                  _buildDesdeAnalisisBanner(theme)
                else
                  _buildImageSelector(theme),
                const SizedBox(height: 16),
                if (_cargando) _buildLoading(theme),
                if (_error != null) _buildError(theme),
                if (_resultado != null) ..._buildPasos(theme),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesdeAnalisisBanner(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado azul
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A3A5C), Color(0xFF0D6EFD)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_fix_high_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Pipeline del último análisis',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
                // Botón para cambiar imagen
                GestureDetector(
                  onTap: () => setState(() {
                    _desdeAnalisis = false;
                    _resultado = null;
                    _imagePath = null;
                    _error = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white38),
                    ),
                    child: const Text('Cambiar imagen',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          // Vista previa de la imagen analizada
          if (_imagePath != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(_imagePath!),
                  height: 130,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageSelector(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D6EFD).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image_search_rounded,
                      color: Color(0xFF0D6EFD), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Selecciona una imagen',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('La app mostrará cada paso del preprocesamiento',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _elegirImagen(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Cámara'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _elegirImagen(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Galería'),
                  ),
                ),
              ],
            ),
            if (_imagePath != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(_imagePath!),
                    height: 120, width: double.infinity, fit: BoxFit.cover),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text('Procesando en el servidor…',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text('Aplicando CLAHE, Unsharp masking y análisis de dominio',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: theme.colorScheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPasos(ThemeData theme) {
    final r = _resultado!;
    final esPhone = r['es_telefono'] as bool? ?? false;
    final tamOrig = r['tam_original'] as String? ?? '?';
    final nPatches = r['n_patches'] as int? ?? 1;

    final pasos = [
      _PasoInfo(
        numero: 1,
        titulo: 'Imagen original',
        descripcion: 'Resolución $tamOrig px. Sin ningún procesamiento.',
        icono: Icons.image_rounded,
        color: const Color(0xFF5C6BC0),
        b64key: 'paso1_original',
      ),
      _PasoInfo(
        numero: 2,
        titulo: 'CLAHE (Contraste adaptativo)',
        descripcion:
            'Clip limit=3.0, tile 8×8. Mejora el contraste local sin saturar zonas brillantes.',
        icono: Icons.brightness_6_rounded,
        color: const Color(0xFF00897B),
        b64key: 'paso2_clahe',
      ),
      _PasoInfo(
        numero: 3,
        titulo: 'Unsharp Masking (Nitidez)',
        descripcion:
            'Kernel σ=2.0, factor 1.35. Resalta bordes de vesículas e hifas.',
        icono: Icons.blur_off_rounded,
        color: const Color(0xFFE65100),
        b64key: 'paso3_unsharp',
      ),
      if (esPhone)
        _PasoInfo(
          numero: 4,
          titulo: 'Normalización de dominio (Hist. Matching)',
          descripcion:
              '⚠️ Imagen de teléfono detectada. Se aplica histogram matching con imagen de referencia Keyence para reducir el domain gap.',
          icono: Icons.compare_arrows_rounded,
          color: const Color(0xFFAD1457),
          b64key: 'paso4_dominio',
        )
      else
        _PasoInfo(
          numero: 4,
          titulo: 'Imagen Keyence/Escáner (sin norm. de dominio)',
          descripcion:
              'La imagen tiene perfil de color Keyence/escáner. No se aplica histogram matching.',
          icono: Icons.check_circle_outline_rounded,
          color: const Color(0xFF2E7D32),
          b64key: 'paso4_dominio',
        ),
      _PasoInfo(
        numero: 5,
        titulo: 'División en patches ($nPatches patches de 768×768)',
        descripcion:
            'La imagen se divide en regiones de 768×768 px (tamaño de entrenamiento). Cada patch se analiza por separado con Mask R-CNN.',
        icono: Icons.grid_on_rounded,
        color: const Color(0xFF6A1B9A),
        b64key: 'paso5_patches',
      ),
    ];

    return [
      // Resumen de dominio
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: esPhone
              ? const Color(0xFFFFF3E0)
              : const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: esPhone
                ? const Color(0xFFE65100)
                : const Color(0xFF2E7D32),
          ),
        ),
        child: Row(
          children: [
            Icon(
              esPhone ? Icons.smartphone_rounded : Icons.biotech_rounded,
              color: esPhone
                  ? const Color(0xFFE65100)
                  : const Color(0xFF2E7D32),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    esPhone
                        ? 'Foto de teléfono detectada'
                        : 'Imagen de microscopio/escáner detectada',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: esPhone
                          ? const Color(0xFFE65100)
                          : const Color(0xFF2E7D32),
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    esPhone
                        ? 'Se aplica normalización de color automática para reducir el domain gap con las imágenes Keyence de entrenamiento.'
                        : 'Sin necesidad de normalización de dominio. Dominio coincide con el entrenamiento.',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ...pasos.map((p) => _buildPasoCard(theme, p, r)),
    ];
  }

  Widget _buildPasoCard(ThemeData theme, _PasoInfo paso, Map<String, dynamic> r) {
    final b64 = r[paso.b64key] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header del paso
          Container(
            color: paso.color,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${paso.numero}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    paso.titulo,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ),
                Icon(paso.icono, color: Colors.white70, size: 20),
              ],
            ),
          ),
          // Descripcion
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(paso.descripcion,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          // Imagen procesada
          if (b64 != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Image.memory(
                    base64Decode(b64),
                    fit: BoxFit.fitWidth,
                    width: double.infinity,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PasoInfo {
  final int numero;
  final String titulo;
  final String descripcion;
  final IconData icono;
  final Color color;
  final String b64key;

  const _PasoInfo({
    required this.numero,
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.color,
    required this.b64key,
  });
}
