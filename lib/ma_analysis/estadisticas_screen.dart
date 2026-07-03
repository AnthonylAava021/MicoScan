import 'package:flutter/material.dart';

import 'ma_history_storage.dart';
import 'ma_models.dart';

class EstadisticasScreen extends StatefulWidget {
  const EstadisticasScreen({super.key});

  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {
  List<MaHistorialItem> _historial = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final items = await MaHistoryStorage.cargar();
    if (mounted) setState(() { _historial = items; _cargando = false; });
  }

  // ── Cálculos ────────────────────────────────────────────────────────────────
  int get _totalAnalisis => _historial.length;

  int get _totalApi => _historial
      .where((h) => h.resultado.modo == MaModoInferencia.remoto)
      .length;

  int get _totalLocal => _historial
      .where((h) => h.resultado.modo == MaModoInferencia.local)
      .length;

  Map<String, int> get _conteoEstructuras {
    final m = <String, int>{};
    for (final h in _historial) {
      for (final e in h.resultado.estructuras) {
        m[e.nombre] = (m[e.nombre] ?? 0) + 1;
      }
    }
    return m;
  }

  double get _areaPromedio {
    if (_historial.isEmpty) return 0;
    return _historial
        .map((h) => h.resultado.areaSegmentada)
        .reduce((a, b) => a + b) /
        _historial.length;
  }

  double get _maxArea =>
      _historial.isEmpty
          ? 0
          : _historial
              .map((h) => h.resultado.areaSegmentada)
              .reduce((a, b) => a > b ? a : b);

  double get _latenciaPromedio {
    if (_historial.isEmpty) return 0;
    return _historial
        .map((h) => h.resultado.latenciaMs.toDouble())
        .reduce((a, b) => a + b) /
        _historial.length;
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
            backgroundColor: const Color(0xFF1B5E20),
            flexibleSpace: FlexibleSpaceBar(
              title: const Text('Estadísticas',
                  style: TextStyle(fontSize: 15, color: Colors.white)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.bar_chart_rounded,
                      size: 56, color: Colors.white24),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                onPressed: () { setState(() => _cargando = true); _cargar(); },
                tooltip: 'Recargar',
              ),
            ],
          ),
          if (_cargando)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_historial.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart_rounded,
                        size: 64, color: theme.colorScheme.outline),
                    const SizedBox(height: 16),
                    Text('Sin análisis todavía',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('Analiza una imagen primero.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildResumenCard(theme),
                  const SizedBox(height: 12),
                  _buildModoCard(theme),
                  const SizedBox(height: 12),
                  _buildEstructurasCard(theme),
                  const SizedBox(height: 12),
                  _buildAreaCard(theme),
                  const SizedBox(height: 12),
                  _buildRendimientoCard(theme),
                  const SizedBox(height: 12),
                  _buildHistoricoCard(theme),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResumenCard(ThemeData theme) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_rounded, color: Color(0xFF1B5E20)),
                const SizedBox(width: 8),
                Text('Resumen general',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatChip('$_totalAnalisis', 'Análisis\ntotales',
                    Icons.biotech_rounded, const Color(0xFF1565C0)),
                _buildStatChip(
                    '${(_areaPromedio * 100).toStringAsFixed(1)}%',
                    'Área media\ncolonizada',
                    Icons.area_chart_rounded,
                    const Color(0xFF1B5E20)),
                _buildStatChip(
                    '${(_latenciaPromedio / 1000).toStringAsFixed(1)}s',
                    'Latencia\npromedio',
                    Icons.timer_outlined,
                    const Color(0xFFE65100)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(
      String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }

  Widget _buildModoCard(ThemeData theme) {
    final total = _totalAnalisis;
    final apiPct = total > 0 ? _totalApi / total : 0.0;
    final localPct = total > 0 ? _totalLocal / total : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Modo de inferencia',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            _buildBarRow('API (Mask R-CNN)', _totalApi, apiPct,
                const Color(0xFF0D6EFD)),
            const SizedBox(height: 8),
            _buildBarRow('Local (ONNX)', _totalLocal, localPct,
                const Color(0xFF43A047)),
          ],
        ),
      ),
    );
  }

  Widget _buildBarRow(String label, int count, double pct, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text('$count  ${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildEstructurasCard(ThemeData theme) {
    final conteos = _conteoEstructuras;
    if (conteos.isEmpty) return const SizedBox.shrink();
    final total = conteos.values.fold(0, (a, b) => a + b);
    final colors = {
      'Arbúsculo': const Color(0xFFDC3232),
      'Vesícula':  const Color(0xFF32C864),
      'Hifa':      const Color(0xFF3282FF),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.scatter_plot_rounded, color: Color(0xFF6A1B9A)),
                const SizedBox(width: 8),
                Text('Estructuras detectadas',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            ...conteos.entries.map((e) {
              final color = colors[e.key] ?? theme.colorScheme.primary;
              final pct   = total > 0 ? e.value / total : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10, height: 10,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(e.key,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                        Text('${e.value} análisis',
                            style: TextStyle(
                                fontSize: 12, color: color,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 8,
                        backgroundColor: color.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildAreaCard(ThemeData theme) {
    final areas = _historial
        .map((h) => h.resultado.areaSegmentada * 100)
        .toList();
    if (areas.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.area_chart_rounded, color: Color(0xFF1B5E20)),
                const SizedBox(width: 8),
                Text('Área colonizada',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildAreaStat('Promedio',
                    '${(_areaPromedio * 100).toStringAsFixed(2)}%',
                    const Color(0xFF1B5E20)),
                _buildAreaStat('Máximo',
                    '${(_maxArea * 100).toStringAsFixed(2)}%',
                    const Color(0xFFE65100)),
                _buildAreaStat('Muestras', '${areas.length}',
                    const Color(0xFF1565C0)),
              ],
            ),
            const SizedBox(height: 16),
            // Mini gráfico de barras de área por análisis
            SizedBox(
              height: 60,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: areas.take(20).map((a) {
                  final h = (_maxArea > 0)
                      ? (a / (_maxArea * 100)) * 60
                      : 4.0;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      height: h.clamp(4.0, 60.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B5E20).withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 4),
            Text('Últimos ${areas.take(20).length} análisis',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      ),
    );
  }

  Widget _buildAreaStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: theme.colorScheme.outline)),
        ],
      ),
    );
  }

  ThemeData get theme => Theme.of(context);

  Widget _buildRendimientoCard(ThemeData theme) {
    final apiItems = _historial
        .where((h) => h.resultado.modo == MaModoInferencia.remoto)
        .toList();
    final latApi = apiItems.isEmpty
        ? 0.0
        : apiItems.map((h) => h.resultado.latenciaMs).reduce((a, b) => a + b) /
            apiItems.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed_rounded, color: Color(0xFFE65100)),
                const SizedBox(width: 8),
                Text('Rendimiento',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Latencia promedio total',
                '${(_latenciaPromedio / 1000).toStringAsFixed(2)} s'),
            _buildInfoRow('Latencia promedio API',
                apiItems.isEmpty
                    ? '—'
                    : '${(latApi / 1000).toStringAsFixed(2)} s'),
            _buildInfoRow('Modo más usado',
                _totalApi >= _totalLocal ? 'API (Mask R-CNN)' : 'Local (ONNX)'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: Colors.black54))),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildHistoricoCard(ThemeData theme) {
    final recientes = _historial.take(5).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded, color: Color(0xFF1565C0)),
                const SizedBox(width: 8),
                Text('Últimos análisis',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            ...recientes.map((h) => _buildHistItem(theme, h)),
          ],
        ),
      ),
    );
  }

  Widget _buildHistItem(ThemeData theme, MaHistorialItem h) {
    final r = h.resultado;
    final fecha = '${h.fecha.day}/${h.fecha.month} ${h.fecha.hour}:${h.fecha.minute.toString().padLeft(2,'0')}';
    final isApi = r.modo == MaModoInferencia.remoto;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isApi
                  ? const Color(0xFF0D6EFD).withValues(alpha: 0.1)
                  : const Color(0xFF43A047).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isApi ? Icons.cloud_done_rounded : Icons.offline_bolt_rounded,
              size: 18,
              color: isApi ? const Color(0xFF0D6EFD) : const Color(0xFF43A047),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.estructuras.isEmpty
                      ? 'Sin estructuras'
                      : r.estructuras.map((e) => e.nombre).join(', '),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Área: ${(r.areaSegmentada * 100).toStringAsFixed(1)}%  •  ${r.latenciaMs}ms  •  $fecha',
                  style: TextStyle(
                      fontSize: 10, color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Badge modelo (M1/M2/Dual) + indicador colonización
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isApi
                      ? const Color(0xFF0D6EFD).withValues(alpha: 0.12)
                      : const Color(0xFF43A047).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  r.modelo.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isApi ? const Color(0xFF0D6EFD) : const Color(0xFF43A047),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: r.colonizacion
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFB71C1C),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    r.colonizacion ? 'Col.' : 'No col.',
                    style: TextStyle(
                      fontSize: 9,
                      color: r.colonizacion
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFB71C1C),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
