import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'camera_capture_screen.dart';
import 'amf_local_classifier.dart';
import 'dev_http_client.dart';
import 'ma_api_config.dart';
import 'ma_export_service.dart';
import 'ma_history_storage.dart';
import 'ma_image_processor.dart';
import 'ma_inference_service.dart';
import 'ma_models.dart';
import 'ma_pipeline_store.dart';
import 'preprocessing_pipeline_screen.dart';

class SegmentacionClasificacionScreen extends StatefulWidget {
  const SegmentacionClasificacionScreen({super.key});

  @override
  State<SegmentacionClasificacionScreen> createState() => _SegmentacionClasificacionScreenState();
}

class _SegmentacionClasificacionScreenState extends State<SegmentacionClasificacionScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  late final TabController _tabs;

  String? _imagenPath;
  MaResultadoAnalisis? _resultado;
  bool _procesando = false;
  bool _mostrarMascara = true;
  bool _mostrarGradCam = false;
  double _umbral = 0.35;
  MaModoInferencia _modo = MaModoInferencia.local;
  // v2 — API siempre usa M2; visualización GT o Máscaras
  final MaModelo  _modeloSeleccionado = MaModelo.m2;   // API: siempre M2
  MaModoViz _modoViz = MaModoViz.gtStyle;
  List<MaHistorialItem> _historial = [];

  // Estado de carga del modelo ONNX
  bool _modeloCargado = false;
  bool _modeloCargando = false;
  String _estadoModelo = 'Modelo no cargado';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    MaApiConfig.load();          // cargar URL guardada al abrir pantalla
    _cargarHistorial();
    // Pre-calentar el modelo local en segundo plano
    _preCalentarModelo();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargarHistorial() async {
    final items = await MaHistoryStorage.cargar();
    if (mounted) setState(() => _historial = items);
  }

  /// Pre-calienta el clasificador ONNX al abrir la pantalla.
  /// La primera vez extrae el modelo (~94 MB) al almacenamiento local;
  /// las siguientes veces lo reutiliza del disco (instantáneo).
  Future<void> _preCalentarModelo() async {
    if (_modeloCargado || _modeloCargando) return;
    if (mounted) setState(() { _modeloCargando = true; _estadoModelo = 'Preparando modelo local…'; });
    try {
      await AmfLocalClassifier.instance.load();
      if (mounted) setState(() { _modeloCargado = true; _estadoModelo = 'Modelo listo ✓'; });
    } catch (e) {
      if (mounted) setState(() { _estadoModelo = 'Error al cargar modelo: $e'; });
    } finally {
      if (mounted) setState(() => _modeloCargando = false);
    }
  }

  Future<void> _abrirCamara() async {
    final path = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (path != null) _setImagen(path);
  }

  Future<void> _abrirGaleria() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (file == null) return;
      await MaImageProcessor.validarYCargar(file.path);
      _setImagen(file.path);
    } catch (e) {
      _snack(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void _setImagen(String path) {
    setState(() {
      _imagenPath = path;
      _resultado = null;
    });
  }

  /// Llama /api/preprocess en background y guarda en el store global
  Future<void> _dispararPreprocesamiento(String path) async {
    final store = MaPipelineStore.instance;
    store.imagePath = path;
    store.preprocessResult = null;
    store.error = null;
    store.loading = true;
    try {
      final bytes = await File(path).readAsBytes();
      final uri = Uri.parse('${MaApiConfig.baseUrl}/api/preprocess');
      final req = http.MultipartRequest('POST', uri)
        ..headers['ngrok-skip-browser-warning'] = 'true'
        ..headers['User-Agent'] = 'MicoScan-App/1.0'
        ..headers['Accept'] = 'application/json'
        ..files.add(http.MultipartFile.fromBytes('image', bytes, filename: 'img.jpg'));
      final client = createDevHttpClient();
      final streamed = await client.send(req).timeout(const Duration(seconds: 60));
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200) {
        store.preprocessResult = jsonDecode(resp.body) as Map<String, dynamic>;
      } else {
        store.error = 'Error ${resp.statusCode}';
      }
    } catch (e) {
      store.error = e.toString();
    } finally {
      store.loading = false;
    }
  }

  Future<void> _analizar() async {
    if (_imagenPath == null || _procesando) return;
    setState(() => _procesando = true);
    // Lanzar preprocesamiento en background en paralelo
    _dispararPreprocesamiento(_imagenPath!);
    try {
      MaResultadoAnalisis resultado;
      if (_modo == MaModoInferencia.local) {
        resultado = await MaInferenceService.inferirLocal(
          imagePath: _imagenPath!,
          umbralBrillo: _umbral,
        );
      } else if (_modeloSeleccionado == MaModelo.dual) {
        resultado = await MaInferenceService.inferirDual(
          imagePath: _imagenPath!,
          modoViz: _modoViz,
        );
      } else {
        resultado = await MaInferenceService.inferirRemoto(
          imagePath: _imagenPath!,
          modelo:  _modeloSeleccionado,
          modoViz: _modoViz,
        );
      }

      final source = await MaImageProcessor.validarYCargar(_imagenPath!);
      final thumb = await MaImageProcessor.guardarMiniatura(
        source,
        await MaImageProcessor.workDirectory(),
      );

      final item = MaHistorialItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fecha: DateTime.now(),
        imagenPath: _imagenPath!,
        thumbnailPath: thumb,
        resultado: resultado,
      );
      await MaHistoryStorage.guardar(item);
      await _cargarHistorial();

      if (!mounted) return;
      setState(() => _resultado = resultado);
    } catch (e, st) {
      debugPrint('[MicoScan] ERROR en análisis: $e\n$st');
      if (mounted) _snack(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
  String? get _imagenVisual {
    if (_resultado == null) return _imagenPath;
    if (_mostrarGradCam && _resultado!.gradCamPath != null) {
      return _resultado!.gradCamPath;
    }
    // En modo remoto, respetamos la máscara
    if (_resultado!.modo == MaModoInferencia.remoto) {
      return _mostrarMascara ? (_resultado!.overlayPath ?? _imagenPath) : _imagenPath;
    }
    // En modo local (offline), SIEMPRE devolvemos la imagen original limpia (sin máscaras fúngicas pintadas)
    return _imagenPath;
  }

  /// Diálogo para cambiar la URL del servidor (ngrok / Cloudflare / IP local).
  Future<void> _mostrarDialogUrl() async {
    final ctrl = TextEditingController(text: MaApiConfig.baseUrl);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.wifi_tethering_rounded, size: 20),
          SizedBox(width: 8),
          Text('URL del servidor', style: TextStyle(fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pega aquí la URL de ngrok o tu servidor:\n'
              '(sin barra al final)',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'https://xxxx.ngrok-free.app',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await MaApiConfig.resetToDefault();
              ctrl.text = MaApiConfig.baseUrl;
            },
            child: const Text('Restaurar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final url = ctrl.text.trim();
              if (url.isNotEmpty) {
                await MaApiConfig.setBaseUrl(url);
                if (mounted) {
                  _snack('URL guardada: ${MaApiConfig.baseUrl}');
                  setState(() {});
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FC),
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: _mostrarDialogUrl,
          child: const Text('Segmentar imagen MA'),
        ),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Análisis', icon: Icon(Icons.biotech_rounded)),
            Tab(text: 'Historial', icon: Icon(Icons.history_rounded)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildAnalisisTab(theme),
          _buildHistorialTab(theme),
        ],
      ),
    );
  }

  Widget _buildAnalisisTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Adquisición', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _abrirCamara,
                        icon: const Icon(Icons.photo_camera_rounded),
                        label: const Text('Cámara'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _abrirGaleria,
                        icon: const Icon(Icons.photo_library_rounded),
                        label: const Text('Galería'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'JPG/PNG · mínimo ${MaImageProcessor.minSize}×${MaImageProcessor.minSize} px',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Procesos de análisis', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                // Banner de estado del modelo local
                if (_modo == MaModoInferencia.local)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _modeloCargado
                          ? Colors.green.shade50
                          : _modeloCargando
                              ? Colors.blue.shade50
                              : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _modeloCargado
                            ? Colors.green.shade300
                            : _modeloCargando
                                ? Colors.blue.shade300
                                : Colors.orange.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (_modeloCargando)
                          const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            _modeloCargado ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                            size: 16,
                            color: _modeloCargado ? Colors.green.shade700 : Colors.orange.shade700,
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _estadoModelo,
                            style: TextStyle(
                              fontSize: 12,
                              color: _modeloCargado
                                  ? Colors.green.shade800
                                  : _modeloCargando
                                      ? Colors.blue.shade800
                                      : Colors.orange.shade800,
                            ),
                          ),
                        ),
                        if (!_modeloCargado && !_modeloCargando)
                          TextButton(
                            onPressed: _preCalentarModelo,
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                            child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                // ── Modo inferencia: Local / API ──────────────────────────
                SegmentedButton<MaModoInferencia>(
                  segments: const [
                    ButtonSegment(
                      value: MaModoInferencia.local,
                      label: Text('Local'),
                      icon: Icon(Icons.offline_bolt_rounded),
                    ),
                    ButtonSegment(
                      value: MaModoInferencia.remoto,
                      label: Text('API'),
                      icon: Icon(Icons.cloud_upload_rounded),
                    ),
                  ],
                  selected: {_modo},
                  onSelectionChanged: (s) => setState(() => _modo = s.first),
                ),
                if (_modo == MaModoInferencia.remoto) ...[
                  // ── Visualización: solo GT Style o Máscaras ─────────────
                  const SizedBox(height: 12),
                  Text('Visualización', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  SegmentedButton<MaModoViz>(
                    segments: const [
                      ButtonSegment(
                        value: MaModoViz.gtStyle,
                        label: Text('Segmentar'),
                        icon: Icon(Icons.crop_square_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: MaModoViz.masks,
                        label: Text('Máscaras'),
                        icon: Icon(Icons.blur_on_rounded, size: 16),
                      ),
                    ],
                    selected: {_modoViz},
                    onSelectionChanged: (s) => setState(() => _modoViz = s.first),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: (_imagenPath == null || _procesando ||
                              (_modo == MaModoInferencia.local && !_modeloCargado))
                      ? null
                      : _analizar,
                  icon: _procesando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    _procesando
                        ? 'Procesando…'
                        : (_modo == MaModoInferencia.local && !_modeloCargado)
                            ? 'Esperando modelo…'
                            : 'Ejecutar análisis',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Visualización', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                // Imagen reducida a 4:3 para que las métricas queden visibles
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _imagenVisual == null
                        ? Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Center(child: Text('Sin imagen')),
                          )
                        : InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 4,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(File(_imagenVisual!), fit: BoxFit.cover),
                                if (_resultado != null && 
                                    (_resultado!.modo == MaModoInferencia.local || 
                                     (_resultado!.modo == MaModoInferencia.remoto && !_mostrarMascara)))
                                  CustomPaint(
                                    painter: _BoundingBoxesPainter(_resultado!.cajas),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
                if (_resultado != null) ...[
                  const SizedBox(height: 12),
                  // ── Métricas por clase (visibles sin scrollear) ─────────
                  _buildClasesCompacto(theme, _resultado!),
                  const SizedBox(height: 4),
                  if (_resultado!.modo == MaModoInferencia.remoto)
                    Row(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('Máscara', style: TextStyle(fontSize: 13)),
                          value: _mostrarMascara,
                          onChanged: (v) => setState(() {
                            _mostrarMascara = v;
                            if (v) _mostrarGradCam = false;
                          }),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('Grad-CAM', style: TextStyle(fontSize: 13)),
                          value: _mostrarGradCam,
                          onChanged: (v) => setState(() {
                            _mostrarGradCam = v;
                            if (v) _mostrarMascara = false;
                          }),
                        ),
                      ].map((w) => Expanded(child: w)).toList(),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (_resultado != null) ...[
          const SizedBox(height: 12),
          _buildResultadosCard(theme, _resultado!),
          const SizedBox(height: 12),
          if (_resultado!.patches.isNotEmpty)
            _buildPatchesCard(theme, _resultado!.patches),
          const SizedBox(height: 12),
          _buildExportCard(_resultado!),
          const SizedBox(height: 12),
          _buildVerPipelineBtn(theme),
        ],
      ],
    );
  }

  // ── Cuadrícula de patches 768×768 ──────────────────────────────────────────
  static const _patchClsColors = {
    'Arbúsculo': Color(0xFFDC3232),  // rojo
    'Vesícula':  Color(0xFF32C864),  // verde
    'Hifa':      Color(0xFF3282FF),  // azul
  };

  Widget _buildVerPipelineBtn(ThemeData theme) {
    final store = MaPipelineStore.instance;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3A5C), Color(0xFF0D6EFD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D6EFD).withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const PreprocesarPipelineScreen(),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    store.loading
                        ? Icons.hourglass_top_rounded
                        : Icons.auto_fix_high_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ver Pipeline de Preprocesamiento',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        store.loading
                            ? 'Preparando visualización...'
                            : store.preprocessResult != null
                                ? 'CLAHE → Unsharp → Hist. Matching → Patches'
                                : 'Toca para ver cómo se procesó la imagen',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white54, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPatchesCard(ThemeData theme, List<MaPatchInfo> patches) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.grid_view_rounded, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Patches analizados (${patches.length})',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '768×768 px c/u',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Leyenda de colores
            Wrap(
              spacing: 10,
              children: _patchClsColors.entries.map((e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10,
                    decoration: BoxDecoration(color: e.value, shape: BoxShape.circle)),
                  const SizedBox(width: 3),
                  Text(e.key, style: const TextStyle(fontSize: 10)),
                ],
              )).toList(),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: patches.length,
              itemBuilder: (ctx, i) => _buildPatchTile(theme, patches[i], i),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatchTile(ThemeData theme, MaPatchInfo p, int idx) {
    // Color dominante según la clase con más detecciones
    Color borderColor = Colors.grey.shade300;
    if (p.nDets > 0) {
      final dominant = p.conteos.entries
          .where((e) => e.value > 0)
          .fold<MapEntry<String,int>?>(null, (prev, e) =>
              prev == null || e.value > prev.value ? e : prev);
      if (dominant != null) {
        borderColor = _patchClsColors[dominant.key] ?? theme.colorScheme.primary;
      }
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: p.nDets > 0 ? 2.5 : 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail del patch
            if (p.thumbnailB64 != null)
              Image.memory(
                base64Decode(p.thumbnailB64!),
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            else
              Container(color: Colors.grey.shade200,
                child: const Center(child: Icon(Icons.image_outlined, size: 24))),
            // Badge con número de detecciones
            Positioned(
              bottom: 3, right: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: p.nDets > 0 ? borderColor.withValues(alpha: 0.9) : Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${p.nDets}',
                  style: const TextStyle(fontSize: 10, color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            // Etiqueta de posición
            Positioned(
              top: 3, left: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'P${idx + 1}',
                  style: const TextStyle(fontSize: 9, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Barras de confianza compactas (una por clase) ──────────────────────────
  static const _coloresClase = {
    'Arbúsculo': Color(0xFF2E7D32), // verde oscuro
    'Vesícula':  Color(0xFF6A1B9A), // violeta
    'Hifa':      Color(0xFFE65100), // naranja
  };

  Widget _buildClasesCompacto(ThemeData theme, MaResultadoAnalisis r) {
    if (r.estructuras.isEmpty) return const SizedBox.shrink();
    return Column(
      children: r.estructuras.map((e) {
        final color = _coloresClase[e.nombre] ?? theme.colorScheme.primary;
        final pct   = e.confianza;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  e.nombre,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 10,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                child: Text(
                  '${(pct * 100).toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Badge prominente que muestra si hay colonización micorrízica detectada.
  Widget _buildColonizacionBadge(MaResultadoAnalisis r) {
    final hay  = r.colonizacion;
    final color = hay ? const Color(0xFF2E7D32) : const Color(0xFFB71C1C);
    final bgCol = hay ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgCol,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(
            hay ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hay ? 'Colonización Detectada' : 'Sin Colonización',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  hay
                      ? 'La raíz presenta hongos micorrízicos arbusculares'
                      : 'No se detectaron estructuras fúngicas significativas',
                  style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Fila de contadores: Arbúsculos N | Vesículas N | Hifas N
  Widget _buildCountsRow(MaResultadoAnalisis r) {
    final items = [
      ('Arbúsculos', r.counts['arbuscule'] ?? 0, const Color(0xFFDC3232)),
      ('Vesículas',  r.counts['vesicle']   ?? 0, const Color(0xFF32C864)),
      ('Hifas',      r.counts['hypha']     ?? 0, const Color(0xFF3282FF)),
    ];
    return Row(
      children: items.map((item) {
        final (label, count, color) = item;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.9)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRfChips() {
    return const Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        Chip(label: Text('RF-01 Cámara')),
        Chip(label: Text('RF-02 Galería')),
        Chip(label: Text('RF-03 Edge')),
        Chip(label: Text('RF-04 API')),
        Chip(label: Text('RF-08 Historial')),
        Chip(label: Text('RF-09 Exportar')),
      ],
    );
  }

  Widget _buildResultadosCard(ThemeData theme, MaResultadoAnalisis r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Encabezado ──────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text('Resultados', style: theme.textTheme.titleMedium),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: r.offline ? Colors.indigo.shade50 : Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: r.offline ? Colors.indigo.shade200 : Colors.teal.shade200,
                    ),
                  ),
                  child: Text(
                    r.offline ? 'Modelo Local' : r.modelo.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: r.offline ? Colors.indigo.shade700 : Colors.teal.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Badge colonización ──────────────────────────────────────────
            _buildColonizacionBadge(r),
            const SizedBox(height: 10),
            // ── Contadores por clase ────────────────────────────────────────
            if (r.counts.isNotEmpty) _buildCountsRow(r),
            const SizedBox(height: 12),
            // ── Detección principal ─────────────────────────────────────────
            if (r.principal != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_coloresClase[r.principal!.nombre] ?? theme.colorScheme.primary).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (_coloresClase[r.principal!.nombre] ?? theme.colorScheme.primary).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estructura principal detectada',
                      style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.principal!.nombre,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: _coloresClase[r.principal!.nombre] ?? theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${(r.principal!.confianza * 100).toStringAsFixed(1)}% de confianza',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // ── Distribución por clase ──────────────────────────────────────
            Text('Probabilidad por estructura', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _buildClasesCompacto(theme, r),
            const Divider(height: 20),
            // ── Métricas adicionales ────────────────────────────────────────
            Row(
              children: [
                _metricaTile(
                  label: 'Área segmentada',
                  value: '${(r.areaSegmentada * 100).toStringAsFixed(1)}%',
                  icon: Icons.crop_free_rounded,
                  theme: theme,
                ),
                const SizedBox(width: 12),
                _metricaTile(
                  label: 'Total det.',
                  value: r.counts.isNotEmpty
                      ? r.totalDetecciones.toString()
                      : r.cajas.length.toString(),
                  icon: Icons.table_chart_rounded,
                  theme: theme,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Resumen textual ─────────────────────────────────────────────
            Text(
              r.resumen,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricaTile({required String label, required String value, required IconData icon, required ThemeData theme}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildExportCard(MaResultadoAnalisis r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Exportar / compartir', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                final path = r.overlayPath ?? r.imagenOriginalPath;
                MaExportService.compartirImagen(path);
              },
              icon: const Icon(Icons.share_rounded),
              label: const Text('Compartir imagen resultado'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => MaExportService.compartirInformePdf(r),
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('Exportar informe PDF'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorialTab(ThemeData theme) {
    if (_historial.isEmpty) {
      return const Center(child: Text('Sin análisis previos'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _historial.length,
      itemBuilder: (context, index) {
        final item = _historial[index];
        final principal = item.resultado.principal;
        return Card(
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(item.thumbnailPath),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
              ),
            ),
            title: Text(
              principal?.nombre ?? 'Análisis',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${item.fecha.day}/${item.fecha.month}/${item.fecha.year} · '
              '${(principal?.confianza ?? 0) * 100}%',
            ),
            onTap: () {
              setState(() {
                _imagenPath = item.imagenPath;
                _resultado = item.resultado;
              });
              _tabs.animateTo(0);
            },
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await MaHistoryStorage.eliminar(item.id);
                await _cargarHistorial();
              },
            ),
          ),
        );
      },
    );
  }
}

class _BoundingBoxesPainter extends CustomPainter {
  final List<MaBoundingBox> cajas;

  _BoundingBoxesPainter(this.cajas);

  @override
  void paint(Canvas canvas, Size size) {
    if (cajas.isEmpty) return;
    const ref = 224.0;
    final sx = size.width / ref;
    final sy = size.height / ref;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF0B57D0);

    for (final c in cajas) {
      final rect = Rect.fromLTWH(
        c.rect.left * sx,
        c.rect.top * sy,
        c.rect.width * sx,
        c.rect.height * sy,
      );
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxesPainter oldDelegate) =>
      oldDelegate.cajas != cajas;
}

