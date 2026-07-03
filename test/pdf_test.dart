import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:micoscan/ma_analysis/ma_models.dart';

void main() {
  test('Test PDF generation', () async {
    final resultado = MaResultadoAnalisis(
      modo: MaModoInferencia.remoto,
      imagenOriginalPath: 'test.jpg',
      overlayPath: 'overlay.jpg',
      estructuras: [
        MaEstructuraDetectada(nombre: 'Arbúsculo', confianza: 0.527),
        MaEstructuraDetectada(nombre: 'Hifa', confianza: 0.404),
        MaEstructuraDetectada(nombre: 'Vesícula', confianza: 0.305),
      ],
      cajas: [],
      resumen: 'Test summary with á é í ó ú ñ',
      areaSegmentada: 0.082,
      latenciaMs: 146,
      offline: false,
      modelo: MaModelo.m2,
      modoViz: MaModoViz.gtStyle,
      colonizacion: true,
      detecciones: [],
      counts: {
        'arbuscule': 5,
        'vesicle': 32,
        'hypha': 7,
      },
    );

    final doc = pw.Document();
    final ahora = DateTime.now();
    final fecha = '${ahora.day.toString().padLeft(2, '0')}/${ahora.month.toString().padLeft(2, '0')}/${ahora.year}';

    const azulUPS = PdfColor.fromInt(0xFF0D3E7D);
    const verdeOK = PdfColor.fromInt(0xFF2E7D32);
    const rojoNO = PdfColor.fromInt(0xFFB71C1C);
    const grisText = PdfColor.fromInt(0xFF424242);

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

    final maxCount = resultado.counts.values.fold(0, (max, v) => v > max ? v : max);
    const chartHeight = 80.0;

    pw.Widget _barraGrafico(String etiqueta, int count, PdfColor color) {
      final porcentaje = maxCount > 0 ? count / maxCount : 0.0;
      final alturaBarra = porcentaje * chartHeight;
      return pw.Column(
        children: [
          pw.Container(
            height: chartHeight,
            alignment: pw.Alignment.bottomCenter,
            child: pw.Container(
              width: 32,
              height: alturaBarra > 0 ? alturaBarra : 2,
              decoration: pw.BoxDecoration(
                color: color,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text('$count', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.Text(etiqueta, style: const pw.TextStyle(fontSize: 9, color: grisText)),
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
                      padding: const pw.EdgeInsets.symmetric(vertical: 8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: const PdfColor.fromInt(0xFFE0E0E0)),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
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

          pw.SizedBox(height: 14),

          // ── Conteo por clase ───────────────────────────────────────────
          pw.Text('Detecciones por clase',
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
              2: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE3F2FD)),
                children: ['Estructura', 'N', 'Confianza media'].map((h) =>
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

          // ── Resumen narrativo ──────────────────────────────────────────
          pw.Text('Resumen',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: azulUPS,
              )),
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF5F5F5),
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Text(resultado.resumen,
                style: const pw.TextStyle(fontSize: 10, color: grisText)),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    expect(bytes, isNotEmpty);
    print('PDF bytes length: ${bytes.length}');
  });
}
