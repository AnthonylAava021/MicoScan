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
      text: texto ?? 'Resultado de análisis MicoTax - MA',
    );
  }

  static Future<void> compartirInformePdf(MaResultadoAnalisis resultado) async {
    final doc = pw.Document();
    final principal = resultado.principal;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Informe de análisis micorrízico - MicoTax'),
          ),
          pw.Text('Fecha: ${DateTime.now()}'),
          pw.Text('Modo: ${resultado.modo.name}'),
          pw.Text('Latencia: ${resultado.latenciaMs} ms'),
          pw.SizedBox(height: 12),
          pw.Text('Resumen: ${resultado.resumen}'),
          pw.SizedBox(height: 8),
          pw.Text('Área segmentada: ${(resultado.areaSegmentada * 100).toStringAsFixed(1)}%'),
          if (principal != null) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'Estructura principal: ${principal.nombre} (${(principal.confianza * 100).toStringAsFixed(1)}%)',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Text('Estructuras detectadas:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ...resultado.estructuras.map(
            (e) => pw.Bullet(
              text: '${e.nombre}: ${(e.confianza * 100).toStringAsFixed(1)}%',
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Nota: resultado de apoyo diagnóstico. Validar con criterio taxonómico y morfología.',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/informe_ma_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(path);
    await file.writeAsBytes(await doc.save());

    final files = <XFile>[XFile(path)];
    if (resultado.overlayPath != null && File(resultado.overlayPath!).existsSync()) {
      files.add(XFile(resultado.overlayPath!));
    }
    await Share.shareXFiles(files, text: 'Informe MicoTax - segmentación MA');
  }
}
