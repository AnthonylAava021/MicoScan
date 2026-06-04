import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'camera_capture_screen.dart';
import 'ma_export_service.dart';
import 'ma_history_storage.dart';
import 'ma_image_processor.dart';
import 'ma_inference_service.dart';
import 'ma_models.dart';

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
  double _umbral = 0.55;
  MaModoInferencia _modo = MaModoInferencia.local;
  List<MaHistorialItem> _historial = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _cargarHistorial();
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

  Future<void> _analizar() async {
    if (_imagenPath == null || _procesando) return;
    setState(() => _procesando = true);
    try {
      MaResultadoAnalisis resultado;
      if (_modo == MaModoInferencia.local) {
        resultado = await MaInferenceService.inferirLocal(
          imagePath: _imagenPath!,
          umbralBrillo: _umbral,
        );
      } else {
        resultado = await MaInferenceService.inferirRemoto(imagePath: _imagenPath!);
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
    } catch (e) {
      _snack(e.toString().replaceAll('Exception: ', ''));
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
    if (_mostrarMascara && _resultado!.overlayPath != null) {
      return _resultado!.overlayPath;
    }
    return _imagenPath;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FC),
      appBar: AppBar(
        title: const Text('Segmentar imagen MA'),
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
        _buildRfChips(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Adquisición (RF-01 / RF-02)', style: theme.textTheme.titleMedium),
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
                Text('Inferencia (RF-03 / RF-04)', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
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
                if (_modo == MaModoInferencia.local) ...[
                  const SizedBox(height: 12),
                  Text('Umbral segmentación', style: theme.textTheme.labelLarge),
                  Slider(
                    value: _umbral,
                    min: 0.2,
                    max: 0.85,
                    divisions: 13,
                    label: _umbral.toStringAsFixed(2),
                    onChanged: (v) => setState(() => _umbral = v),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _imagenPath == null || _procesando ? null : _analizar,
                  icon: _procesando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(_procesando ? 'Procesando...' : 'Ejecutar análisis'),
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
                Text('Visualización (RF-05–07)', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                AspectRatio(
                  aspectRatio: 1,
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
                                Image.file(File(_imagenVisual!), fit: BoxFit.contain),
                                if (_resultado != null)
                                  CustomPaint(
                                    painter: _BoundingBoxesPainter(_resultado!.cajas),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
                if (_resultado != null) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mostrar máscara (RF-06)'),
                    value: _mostrarMascara,
                    onChanged: (v) => setState(() {
                      _mostrarMascara = v;
                      if (v) _mostrarGradCam = false;
                    }),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mostrar Grad-CAM (RF-07)'),
                    value: _mostrarGradCam,
                    onChanged: (v) => setState(() {
                      _mostrarGradCam = v;
                      if (v) _mostrarMascara = false;
                    }),
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
          _buildExportCard(_resultado!),
        ],
      ],
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
            Text('Clasificación (RF-05)', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(r.resumen, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              'Modo: ${r.modo.name} · ${r.latenciaMs} ms · '
              '${r.offline ? "offline" : "en línea"}',
            ),
            const Divider(height: 20),
            ...r.estructuras.map(
              (e) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(e.nombre),
                trailing: Text('${(e.confianza * 100).toStringAsFixed(1)}%'),
                leading: const Icon(Icons.fiber_manual_record, size: 12),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Área segmentada: ${(r.areaSegmentada * 100).toStringAsFixed(1)}%',
              style: theme.textTheme.bodySmall,
            ),
            if (r.principal != null)
              Text(
                'Zona determinante (Grad-CAM): región con mayor activación sobre ${r.principal!.nombre}.',
                style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
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
            const Text('Exportar / compartir (RF-09)', style: TextStyle(fontWeight: FontWeight.bold)),
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
      return const Center(child: Text('Sin análisis previos (RF-08)'));
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
