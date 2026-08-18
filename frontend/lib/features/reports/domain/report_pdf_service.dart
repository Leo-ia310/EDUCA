import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../grades/domain/entities.dart';

/// Genera el PDF del boletín con base en [ReportCard]. Devuelve bytes listos
/// para compartir/guardar/imprimir con `printing` package.
class ReportPdfService {
  const ReportPdfService();

  Future<Uint8List> buildReportCard(ReportCard card) async {
    final doc = pw.Document(
      title: 'Boletín ${card.periodName} — ${card.studentName}',
    );
    final green = PdfColor.fromInt(0xFF9BE000);
    final dark = PdfColor.fromInt(0xFF1E2218);
    final muted = PdfColor.fromInt(0xFF5C6354);
    final surfaceAlt = PdfColor.fromInt(0xFFF1F4E2);
    final divider = PdfColor.fromInt(0xFFE3E7D2);

    final fmt = DateFormat('d MMM y', 'es');

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 28),
      header: (ctx) => _header(card, green, dark, muted, surfaceAlt, fmt),
      footer: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Divider(color: divider, thickness: 0.5),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Educa360 — Boletín generado',
                  style: pw.TextStyle(fontSize: 8, color: muted)),
              pw.Text(
                'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: muted),
              ),
            ],
          ),
        ],
      ),
      build: (ctx) => [
        _summary(card, green, dark, muted, surfaceAlt),
        pw.SizedBox(height: 18),
        _subjectsTable(card, dark, muted, surfaceAlt, divider),
        pw.SizedBox(height: 18),
        _legend(dark, muted, divider),
      ],
    ));

    return doc.save();
  }

  pw.Widget _header(
    ReportCard card,
    PdfColor green,
    PdfColor dark,
    PdfColor muted,
    PdfColor surface,
    DateFormat fmt,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: green, width: 3),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 40,
            height: 40,
            decoration: pw.BoxDecoration(
              color: green,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              'E360',
              style: pw.TextStyle(
                color: dark,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  card.institutionName,
                  style: pw.TextStyle(
                      color: dark,
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Boletín de calificaciones · ${card.periodName}',
                  style: pw.TextStyle(color: muted, fontSize: 10),
                ),
              ],
            ),
          ),
          pw.Text(
            'Emitido: ${fmt.format(DateTime.now())}',
            style: pw.TextStyle(color: muted, fontSize: 9),
          ),
        ],
      ),
    );
  }

  pw.Widget _summary(
    ReportCard card,
    PdfColor green,
    PdfColor dark,
    PdfColor muted,
    PdfColor surface,
  ) {
    pw.Widget cell(String label, String value) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 8,
                    color: muted,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 12,
                    color: dark,
                    fontWeight: pw.FontWeight.bold)),
          ],
        );
    return pw.Row(
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: surface,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(card.studentName,
                    style: pw.TextStyle(
                        fontSize: 16,
                        color: dark,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(card.gradeLevel,
                    style: pw.TextStyle(fontSize: 10, color: muted)),
                pw.SizedBox(height: 10),
                pw.Row(children: [
                  pw.Expanded(child: cell('Periodo', card.periodName)),
                  pw.Expanded(
                      child: cell(
                          'Asistencia',
                          '${card.attendancePct.toStringAsFixed(1)}%')),
                  pw.Expanded(
                      child: cell(
                          'Posición',
                          '${card.rank} de ${card.totalPeers}')),
                ]),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          flex: 2,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: green,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Promedio general',
                    style: pw.TextStyle(
                        color: dark,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(
                  card.overallAverage.toStringAsFixed(2),
                  style: pw.TextStyle(
                      color: dark,
                      fontSize: 32,
                      fontWeight: pw.FontWeight.bold),
                ),
                if (card.overallLabel != null)
                  pw.Text(
                    card.overallLabel!,
                    style: pw.TextStyle(
                        color: dark,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _subjectsTable(
    ReportCard card,
    PdfColor dark,
    PdfColor muted,
    PdfColor surface,
    PdfColor divider,
  ) {
    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(4),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(1.4),
        3: const pw.FlexColumnWidth(1.4),
        4: const pw.FlexColumnWidth(1.6),
      },
      border: pw.TableBorder.symmetric(
        inside: pw.BorderSide(color: divider, width: 0.5),
      ),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: surface),
          children: [
            _th('Materia', dark),
            _th('Docente', dark),
            _th('Nota', dark, align: pw.TextAlign.right),
            _th('Escala', dark, align: pw.TextAlign.right),
            _th('Estado', dark, align: pw.TextAlign.right),
          ],
        ),
        for (final line in card.lines)
          pw.TableRow(
            children: [
              _cell(line.subjectName, dark, bold: true),
              _cell(line.teacherName, muted),
              _cell(line.finalScore.toStringAsFixed(2), dark,
                  align: pw.TextAlign.right, bold: true),
              _cell(line.qualitativeLabel ?? '—', muted,
                  align: pw.TextAlign.right),
              _cell(line.passed ? 'Aprobado' : 'Reprobado',
                  line.passed
                      ? PdfColor.fromInt(0xFF15803D)
                      : PdfColor.fromInt(0xFFB91C1C),
                  align: pw.TextAlign.right, bold: true),
            ],
          ),
      ],
    );
  }

  pw.Widget _th(String label, PdfColor color, {pw.TextAlign? align}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: pw.Text(
          label,
          textAlign: align,
          style: pw.TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold),
        ),
      );

  pw.Widget _cell(String value, PdfColor color,
          {pw.TextAlign? align, bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: pw.Text(
          value,
          textAlign: align,
          style: pw.TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  pw.Widget _legend(PdfColor dark, PdfColor muted, PdfColor divider) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: divider),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Observaciones',
              style: pw.TextStyle(
                  color: dark,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Este boletín refleja el rendimiento académico del estudiante durante el periodo indicado. '
            'Los criterios de aprobación siguen la escala configurada por la institución.',
            style: pw.TextStyle(color: muted, fontSize: 9, lineSpacing: 1.3),
          ),
        ],
      ),
    );
  }
}
