import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'ma_models.dart';

/// RF-09: exportar y compartir resultados.
class MaExportService {
  static Future<void> compartirImagen(String imagePath, {String? texto}) async {
    await Share.shareXFiles(
      [XFile(imagePath)],
      text: texto ?? 'Resultado de análisis MicoScan - MA',
    );
  }

  static Future<void> compartirInformePdf(MaResultadoAnalisis resultado, {String? text}) async {
    final doc   = pw.Document();
    final ahora = DateTime.now();
    final fecha = '${ahora.day.toString().padLeft(2,'0')}/'
                  '${ahora.month.toString().padLeft(2,'0')}/'
                  '${ahora.year}  '
                  '${ahora.hour.toString().padLeft(2,'0')}:'
                  '${ahora.minute.toString().padLeft(2,'0')}';

    // Colores UPS-GIIAR
    const azulUPS  = PdfColor.fromInt(0xFF0D3E7D);
    const verdeOK  = PdfColor.fromInt(0xFF2E7D32);
    const rojoNO   = PdfColor.fromInt(0xFFB71C1C);
    const grisText = PdfColor.fromInt(0xFF424242);

    // ── Helper para barra de gráfico personalizado ──────────────────────────
    final maxCount = resultado.counts.values.fold(0, (max, v) => v > max ? v : max);
    const chartHeight = 80.0;

    pw.TableRow _fila(String label, String valor, {bool bold = false}) {
      return pw.TableRow(children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text(label,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: grisText,
              )),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text(valor,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              )),
        ),
      ]);
    }

    pw.Widget _barraGrafico(String etiqueta, int count, PdfColor color) {
      final porcentaje = maxCount > 0 ? count / maxCount : 0.0;
      final alturaBarra = porcentaje * chartHeight;
      return pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Container(
            height: chartHeight,
            alignment: pw.Alignment.bottomCenter,
            child: pw.Container(
              width: 20,
              height: alturaBarra > 0 ? alturaBarra : 2,
              decoration: pw.BoxDecoration(
                color: color,
                borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(3)),
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text('$count', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
          pw.Text(etiqueta, style: const pw.TextStyle(fontSize: 8, color: grisText)),
        ],
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (ctx) => pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: azulUPS, width: 2)),
          ),
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('MicoScan - Informe de Análisis Micorrízico',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: azulUPS,
                      )),
                  pw.Text('Universidad Politécnica Salesiana - Grupo GIIAR',
                      style: const pw.TextStyle(fontSize: 9, color: grisText)),
                ],
              ),
              pw.Text('Fecha: $fecha',
                  style: const pw.TextStyle(fontSize: 9, color: grisText)),
            ],
          ),
        ),
        build: (ctx) => [
          pw.SizedBox(height: 16),

          // ── Resultado de colonización ──────────────────────────────────
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: pw.BoxDecoration(
              color: resultado.colonizacion
                  ? const PdfColor.fromInt(0xFFE8F5E9)
                  : const PdfColor.fromInt(0xFFFFEBEE),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              border: pw.Border.all(
                color: resultado.colonizacion ? verdeOK : rojoNO,
                width: 1.5,
              ),
            ),
            child: pw.Text(
              resultado.colonizacion
                  ? '[+] Colonización micorrízica DETECTADA'
                  : '[-] Sin colonización micorrízica significativa',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: resultado.colonizacion ? verdeOK : rojoNO,
              ),
            ),
          ),

          pw.SizedBox(height: 14),

          // ── Fila de Tabla y Gráfico de Barras ────────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Tabla de parámetros
              pw.Expanded(
                flex: 4,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Parámetros del análisis',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: azulUPS,
                        )),
                    pw.SizedBox(height: 6),
                    pw.Table(
                      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE0E0E0)),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(2),
                        1: const pw.FlexColumnWidth(3),
                      },
                      children: [
                        _fila('Modelo',           resultado.modelo.label),
                        _fila('Modo',             resultado.modo == MaModoInferencia.remoto ? 'API (remoto)' : 'Local (ONNX)'),
                        _fila('Área colonizada',  '${(resultado.areaSegmentada * 100).toStringAsFixed(1)} %'),
                        _fila('Latencia',         '${resultado.latenciaMs} ms'),
                        _fila('Total',            '${resultado.counts.values.fold(0, (a, b) => a + b)}', bold: true),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              // Gráfico de Barras visual
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Distribución de estructuras',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: azulUPS,
                        )),
                    pw.SizedBox(height: 6),
                    pw.Container(
                      height: 112,
                      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: const PdfColor.fromInt(0xFFE0E0E0)),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          // Eje Y (Etiquetas de conteo)
                          pw.Container(
                            height: chartHeight,
                            padding: const pw.EdgeInsets.only(right: 6),
                            child: pw.Column(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Text('$maxCount', style: const pw.TextStyle(fontSize: 7.5, color: grisText)),
                                pw.Text('${(maxCount / 2).round()}', style: const pw.TextStyle(fontSize: 7.5, color: grisText)),
                                pw.Text('0', style: const pw.TextStyle(fontSize: 7.5, color: grisText)),
                              ],
                            ),
                          ),
                          // Cuerpo del gráfico (Líneas de cuadrícula + barras)
                          pw.Expanded(
                            child: pw.Stack(
                              children: [
                                // Líneas de cuadrícula horizontales
                                pw.Column(
                                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                  children: [
                                    pw.Container(height: 0.8, color: const PdfColor.fromInt(0xFFE5E7EB)),
                                    pw.Container(height: 0.8, color: const PdfColor.fromInt(0xFFE5E7EB)),
                                    pw.Container(height: 1.2, color: const PdfColor.fromInt(0xFF9CA3AF)), // Línea base eje X
                                  ],
                                ),
                                // Barras
                                pw.Positioned.fill(
                                  child: pw.Row(
                                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                                    children: [
                                      _barraGrafico('Arb.', resultado.counts['arbuscule'] ?? 0, const PdfColor.fromInt(0xFFDC3232)),
                                      _barraGrafico('Ves.',  resultado.counts['vesicle']   ?? 0, const PdfColor.fromInt(0xFF32C864)),
                                      _barraGrafico('Hifas', resultado.counts['hypha']     ?? 0, const PdfColor.fromInt(0xFF3282FF)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 14),

          // ── Conteo por clase ───────────────────────────────────────────
          pw.Text('Métricas detalladas por estructura',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: azulUPS,
              )),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE0E0E0)),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.8),
              3: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE3F2FD)),
                children: ['Estructura', 'N', 'Proporción', 'Confianza media'].map((h) =>
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  )
                ).toList(),
              ),
              ...resultado.estructuras.map((e) {
                final key = e.nombre == 'Arbúsculo' ? 'arbuscule'
                          : e.nombre == 'Vesícula'  ? 'vesicle'
                          : 'hypha';
                final n = resultado.counts[key] ?? 0;
                final totalDets = resultado.totalDetecciones;
                final prop = totalDets > 0 ? (n / totalDets) * 100 : 0.0;
                return pw.TableRow(children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: pw.Text(e.nombre, style: const pw.TextStyle(fontSize: 10)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: pw.Text('$n', style: const pw.TextStyle(fontSize: 10)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: pw.Text('${prop.toStringAsFixed(1)} %', style: const pw.TextStyle(fontSize: 10)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: pw.Text(
                      '${(e.confianza * 100).toStringAsFixed(1)} %',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ),
                ]);
              }),
            ],
          ),

          pw.SizedBox(height: 14),

          // ── Imágenes del Análisis (Segmentación y Grad-CAM) ───────────────
          if ((resultado.overlayPath != null && File(resultado.overlayPath!).existsSync()) ||
              (resultado.gradCamPath != null && File(resultado.gradCamPath!).existsSync())) ...[
            pw.SizedBox(height: 14),
            pw.Text('Visualización del análisis',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: azulUPS,
                )),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (resultado.overlayPath != null && File(resultado.overlayPath!).existsSync())
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('Estructuras predichas', style: const pw.TextStyle(fontSize: 9, color: grisText)),
                        pw.SizedBox(height: 4),
                        pw.Container(
                          height: 180,
                          child: pw.Image(
                            pw.MemoryImage(File(resultado.overlayPath!).readAsBytesSync()),
                            fit: pw.BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (resultado.overlayPath != null && resultado.gradCamPath != null && File(resultado.overlayPath!).existsSync() && File(resultado.gradCamPath!).existsSync())
                  pw.SizedBox(width: 14),
                if (resultado.gradCamPath != null && File(resultado.gradCamPath!).existsSync())
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('Mapa de calor (Grad-CAM)', style: const pw.TextStyle(fontSize: 9, color: grisText)),
                        pw.SizedBox(height: 4),
                        pw.Container(
                          height: 180,
                          child: pw.Image(
                            pw.MemoryImage(File(resultado.gradCamPath!).readAsBytesSync()),
                            fit: pw.BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],

          // ── Lista de detecciones individuales ─────────────────────────
          if (resultado.detecciones.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text('Lista de detecciones (${resultado.detecciones.length})',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: azulUPS,
                )),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE0E0E0)),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.5),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE3F2FD)),
                  children: ['#', 'Clase', 'Score'].map((h) =>
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    )
                  ).toList(),
                ),
                ...resultado.detecciones.asMap().entries.map((entry) {
                  final i   = entry.key + 1;
                  final det = entry.value;
                  return pw.TableRow(children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: pw.Text('$i', style: const pw.TextStyle(fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: pw.Text(det.clase.capitalize(), style: const pw.TextStyle(fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: pw.Text('${(det.score * 100).toStringAsFixed(1)} %',
                          style: const pw.TextStyle(fontSize: 9)),
                    ),
                  ]);
                }),
              ],
            ),
          ],

          pw.SizedBox(height: 20),
          pw.Divider(color: const PdfColor.fromInt(0xFFBDBDBD)),
          pw.SizedBox(height: 6),
          pw.Text(
            'Nota: este informe es de apoyo diagnóstico. Validar con criterio taxonómico y morfología de referencia.\n'
            'Generado por MicoScan v2 - Mask R-CNN ResNet50-FPN v2 - UPS GIIAR',
            style: const pw.TextStyle(fontSize: 8, color: grisText),
          ),
        ],
      ),
    );

    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/informe_micoscan_${ahora.millisecondsSinceEpoch}.pdf';
    final file = File(path);
    await file.writeAsBytes(await doc.save());

    final files = <XFile>[XFile(path)];
    await Share.shareXFiles(files, text: 'Informe MicoScan - Segmentación MA - $fecha');
  }
}

extension _StringExt on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
