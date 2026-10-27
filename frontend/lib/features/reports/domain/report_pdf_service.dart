import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../grades/domain/entities.dart';

/// Recursos opcionales del PDF: tipografía de la app (Inter) y logo. Si faltan,
/// el boletín se genera igual con la tipografía estándar y sin logo.
class ReportPdfAssets {
  const ReportPdfAssets({this.regular, this.bold, this.logo});

  final pw.Font? regular;
  final pw.Font? bold;

  /// PNG/JPG del logo de Nivra.
  final Uint8List? logo;
}

typedef ReportPdfAssetsLoader = Future<ReportPdfAssets?> Function();

/// Genera el PDF del boletín con base en [ReportCard], con el mismo lenguaje
/// visual que la app: azul de marca, bordes tinta gruesos, sombra dura y
/// tarjetas redondeadas. Devuelve bytes listos para compartir/guardar/imprimir
/// con el paquete `printing`.
class ReportPdfService {
  const ReportPdfService({this.loadAssets});

  final ReportPdfAssetsLoader? loadAssets;

  // Paleta de la app (AppColors, modo claro).
  static const _ink = PdfColor.fromInt(0xFF0B1B3A);
  static const _accent = PdfColor.fromInt(0xFF2563EB);
  static const _accentDeep = PdfColor.fromInt(0xFF1D4ED8);
  static const _accentSoft = PdfColor.fromInt(0xFFDCE8FF);
  static const _surfaceAlt = PdfColor.fromInt(0xFFEEF4FF);
  static const _muted = PdfColor.fromInt(0xFF5B6B8C);
  static const _line = PdfColor.fromInt(0xFFDCE6F7);
  static const _white = PdfColors.white;
  static const _success = PdfColor.fromInt(0xFF15803D);
  static const _successSoft = PdfColor.fromInt(0xFFDCFCE7);
  static const _danger = PdfColor.fromInt(0xFFB91C1C);
  static const _dangerSoft = PdfColor.fromInt(0xFFFEE2E2);
  static const _sunSoft = PdfColor.fromInt(0xFFFFF1CC);

  /// Colores de categoría (como las tarjetas pastel por materia de la app).
  static const _subjectDots = [
    PdfColor.fromInt(0xFF2563EB),
    PdfColor.fromInt(0xFFF5A300),
    PdfColor.fromInt(0xFF0FB5A0),
    PdfColor.fromInt(0xFF7C5CFA),
    PdfColor.fromInt(0xFFFF6B4A),
    PdfColor.fromInt(0xFF0EA5E9),
  ];

  static const _border = 1.2;
  static const _shadow = 3.0;

  Future<Uint8List> buildReportCard(ReportCard card) async {
    ReportPdfAssets? assets;
    try {
      assets = await loadAssets?.call();
    } catch (_) {
      assets = null; // sin red/recursos: tipografía estándar
    }
    final theme = assets?.regular != null && assets?.bold != null
        ? pw.ThemeData.withFont(base: assets!.regular!, bold: assets.bold!)
        : null;
    final logo = assets?.logo == null ? null : pw.MemoryImage(assets!.logo!);

    final doc = pw.Document(
      title: 'Boletín ${card.periodName} — ${card.studentName}',
      author: card.institutionName,
      creator: 'Nivra',
      theme: theme,
    );
    final fmt = DateFormat('d MMM y', 'es');
    const shadow = _shadow;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 30, 30, 28),
        header: (ctx) =>
            ctx.pageNumber == 1 ? pw.SizedBox() : _runningHeader(card, logo),
        footer: _footer,
        build: (ctx) => [
          _hero(card, logo, fmt, shadow),
          pw.SizedBox(height: 16),
          _summary(card, shadow),
          pw.SizedBox(height: 18),
          _sectionTitle('Materias'),
          pw.SizedBox(height: 8),
          _subjectsTable(card, shadow),
          pw.SizedBox(height: 18),
          _legend(shadow),
          pw.SizedBox(height: 26),
          _signatures(card),
        ],
      ),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------- bloques

  /// Tarjeta con borde tinta y sombra dura abajo a la derecha.
  pw.Widget _card({
    required pw.Widget child,
    PdfColor fill = _white,
    double radius = 12,
    pw.EdgeInsets padding = const pw.EdgeInsets.all(14),
    double shadow = _shadow,
  }) {
    // La sombra dura se dibuja a mano detrás de la tarjeta, con el mismo radio de
    // esquina (`boxShadow` la deja cuadrada y además rasteriza el PDF).
    return pw.Padding(
      padding: pw.EdgeInsets.only(right: shadow, bottom: shadow),
      child: pw.CustomPaint(
        painter: shadow == 0
            ? null
            : (canvas, size) {
                canvas
                  ..setFillColor(_ink)
                  ..drawRRect(shadow, -shadow, size.x, size.y, radius, radius)
                  ..fillPath();
              },
        child: pw.Container(
          padding: padding,
          decoration: pw.BoxDecoration(
            color: fill,
            border: pw.Border.all(color: _ink, width: _border),
            borderRadius: pw.BorderRadius.circular(radius),
          ),
          child: child,
        ),
      ),
    );
  }

  pw.Widget _logoBox(pw.MemoryImage? logo, {double size = 40}) {
    return pw.Container(
      width: size,
      height: size,
      decoration: pw.BoxDecoration(
        color: _white,
        border: pw.Border.all(color: _ink, width: _border),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      alignment: pw.Alignment.center,
      child: logo == null
          ? pw.Text(
              'N',
              style: pw.TextStyle(
                color: _accent,
                fontSize: size * 0.5,
                fontWeight: pw.FontWeight.bold,
              ),
            )
          : pw.Padding(
              padding: const pw.EdgeInsets.all(3),
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
    );
  }

  pw.Widget _hero(
    ReportCard card,
    pw.MemoryImage? logo,
    DateFormat fmt,
    double shadow,
  ) {
    return _card(
      fill: _accent,
      radius: 16,
      shadow: shadow == 0 ? 0 : shadow + 1,
      padding: const pw.EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _logoBox(logo, size: 46),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'NIVRA · BOLETÍN DE CALIFICACIONES',
                  style: const pw.TextStyle(
                    color: _accentSoft,
                    fontSize: 7.5,
                    letterSpacing: 1.2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  card.institutionName,
                  style: const pw.TextStyle(
                    color: _white,
                    fontSize: 19,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  card.periodName,
                  style: const pw.TextStyle(color: _accentSoft, fontSize: 10),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: pw.BoxDecoration(
              color: _white,
              border: pw.Border.all(color: _ink, width: _border),
              borderRadius: pw.BorderRadius.circular(9),
            ),
            child: pw.Text(
              'Emitido ${fmt.format(DateTime.now())}',
              style: const pw.TextStyle(
                color: _ink,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _statBox(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: pw.BoxDecoration(
        color: _white,
        border: pw.Border.all(color: _ink, width: 1),
        borderRadius: pw.BorderRadius.circular(9),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: const pw.TextStyle(
              fontSize: 6.5,
              color: _muted,
              letterSpacing: 0.8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: const pw.TextStyle(
              fontSize: 11.5,
              color: _ink,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _summary(ReportCard card, double shadow) {
    // Altura fija: dentro de MultiPage la altura es ilimitada y `stretch` no puede igualarlas.
    return pw.SizedBox(
      height: 124,
      child: _summaryRow(card, shadow),
    );
  }

  pw.Widget _summaryRow(ReportCard card, double shadow) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Expanded(
          flex: 3,
          child: _card(
            shadow: shadow,
            fill: _surfaceAlt,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  card.studentName,
                  style: const pw.TextStyle(
                    fontSize: 17,
                    color: _ink,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  card.gradeLevel,
                  style: const pw.TextStyle(fontSize: 10, color: _muted),
                ),
                pw.SizedBox(height: 11),
                pw.Row(
                  children: [
                    pw.Expanded(child: _statBox('Periodo', card.periodName)),
                    pw.SizedBox(width: 7),
                    pw.Expanded(
                      child: _statBox(
                        'Asistencia',
                        card.attendancePct == null
                            ? '-'
                            : '${card.attendancePct!.toStringAsFixed(1)}%',
                      ),
                    ),
                    pw.SizedBox(width: 7),
                    pw.Expanded(
                      child: _statBox(
                        'Posición',
                        card.rank == null || card.totalPeers == null
                            ? 'No disponible'
                            : '${card.rank} de ${card.totalPeers}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          flex: 2,
          child: _card(
            shadow: shadow,
            fill: _accent,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'PROMEDIO GENERAL',
                  style: const pw.TextStyle(
                    color: _accentSoft,
                    fontSize: 7.5,
                    letterSpacing: 1,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  card.hasGrades ? card.overallAverage.toStringAsFixed(2) : '-',
                  style: const pw.TextStyle(
                    color: _white,
                    fontSize: 34,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (card.overallLabel != null) ...[
                  pw.SizedBox(height: 4),
                  _chip(card.overallLabel!, _white, _ink, border: _ink),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _sectionTitle(String text) {
    return pw.Row(
      children: [
        pw.Container(
          width: 4,
          height: 13,
          decoration: pw.BoxDecoration(
            color: _accent,
            borderRadius: pw.BorderRadius.circular(2),
          ),
        ),
        pw.SizedBox(width: 7),
        pw.Text(
          text,
          style: const pw.TextStyle(
            color: _ink,
            fontSize: 12.5,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Widget _chip(
    String label,
    PdfColor fill,
    PdfColor text, {
    PdfColor? border,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: fill,
        border: pw.Border.all(color: border ?? text, width: 0.9),
        borderRadius: pw.BorderRadius.circular(9),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          color: text,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  PdfColor _dotFor(String subject) {
    var hash = 0;
    for (final unit in subject.toLowerCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _subjectDots[hash % _subjectDots.length];
  }

  pw.Widget _subjectsTable(ReportCard card, double shadow) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _accentSoft),
        children: [
          _th('Materia'),
          _th('Docente'),
          _th('Nota', align: pw.TextAlign.right),
          _th('Escala', align: pw.TextAlign.right),
          _th('Estado', align: pw.TextAlign.right),
        ],
      ),
      for (final line in card.lines)
        pw.TableRow(
          children: [
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              child: pw.Row(
                children: [
                  pw.Container(
                    width: 7,
                    height: 7,
                    decoration: pw.BoxDecoration(
                      color: _dotFor(line.subjectName),
                      border: pw.Border.all(color: _ink, width: 0.7),
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  pw.SizedBox(width: 7),
                  pw.Expanded(
                    child: pw.Text(
                      line.subjectName,
                      style: const pw.TextStyle(
                        color: _ink,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _cell(line.teacherName, _muted),
            _cell(
              line.hasGrade ? line.finalScore.toStringAsFixed(2) : '-',
              line.hasGrade && !line.passed ? _danger : _ink,
              align: pw.TextAlign.right,
              bold: true,
              size: 11,
            ),
            _cell(
              line.qualitativeLabel ?? '-',
              _muted,
              align: pw.TextAlign.right,
            ),
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: !line.hasGrade
                    ? _chip('Sin calificar', _surfaceAlt, _muted)
                    : line.passed
                        ? _chip('Aprobado', _successSoft, _success)
                        : _chip('Reprobado', _dangerSoft, _danger),
              ),
            ),
          ],
        ),
    ];
    if (card.lines.length > 14) {
      return pw.Table(
        columnWidths: _columnWidths,
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        border: const pw.TableBorder(
          left: pw.BorderSide(color: _ink, width: _border),
          right: pw.BorderSide(color: _ink, width: _border),
          top: pw.BorderSide(color: _ink, width: _border),
          bottom: pw.BorderSide(color: _ink, width: _border),
          horizontalInside: pw.BorderSide(color: _line, width: 0.8),
        ),
        children: rows,
      );
    }
    return _card(
      shadow: shadow,
      padding: pw.EdgeInsets.zero,
      radius: 12,
      child: pw.ClipRRect(
        horizontalRadius: 10.5,
        verticalRadius: 10.5,
        child: pw.Table(
          columnWidths: _columnWidths,
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _line, width: 0.8),
          ),
          children: rows,
        ),
      ),
    );
  }

  static const _columnWidths = <int, pw.TableColumnWidth>{
    0: pw.FlexColumnWidth(4),
    1: pw.FlexColumnWidth(3.2),
    2: pw.FlexColumnWidth(1.3),
    3: pw.FlexColumnWidth(1.7),
    4: pw.FlexColumnWidth(2),
  };

  pw.Widget _th(String label, {pw.TextAlign? align}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        child: pw.Text(
          label.toUpperCase(),
          textAlign: align,
          style: const pw.TextStyle(
            color: _accentDeep,
            fontSize: 7.5,
            letterSpacing: 0.8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );

  pw.Widget _cell(
    String value,
    PdfColor color, {
    pw.TextAlign? align,
    bool bold = false,
    double size = 9.5,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        child: pw.Text(
          value,
          textAlign: align,
          style: pw.TextStyle(
            color: color,
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  pw.Widget _legend(double shadow) {
    return _card(
      shadow: shadow,
      fill: _sunSoft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Observaciones',
            style: const pw.TextStyle(
              color: _ink,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Este boletín refleja el rendimiento académico del estudiante durante el periodo indicado. '
            'Los criterios de aprobación siguen la escala configurada por la institución.',
            style: const pw.TextStyle(
              color: _ink,
              fontSize: 9,
              lineSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Espacio para la firma del director y el sello del colegio (se rellenan a mano).
  pw.Widget _signatures(ReportCard card) {
    pw.Widget caption(String title, String detail) => pw.Column(
          children: [
            pw.Text(
              title,
              style: const pw.TextStyle(
                color: _ink,
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              detail,
              style: const pw.TextStyle(color: _muted, fontSize: 8),
            ),
          ],
        );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.SizedBox(height: 64),
                pw.Container(height: _border, color: _ink),
                pw.SizedBox(height: 6),
                caption('Firma del director(a)', card.institutionName),
              ],
            ),
          ),
          pw.SizedBox(width: 56),
          pw.Column(
            children: [
              pw.Container(
                width: 84,
                height: 84,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(
                    color: _muted,
                    width: 1,
                    style: pw.BorderStyle.dashed,
                  ),
                ),
                child: pw.Text(
                  'SELLO',
                  style: const pw.TextStyle(
                    color: _line,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              caption('Sello del colegio', card.institutionName),
            ],
          ),
        ],
      ),
    );
  }

  /// Cabecera compacta de las páginas siguientes a la primera.
  pw.Widget _runningHeader(ReportCard card, pw.MemoryImage? logo) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 2)),
      ),
      child: pw.Row(
        children: [
          _logoBox(logo, size: 26),
          pw.SizedBox(width: 9),
          pw.Expanded(
            child: pw.Text(
              '${card.institutionName} · Boletín ${card.periodName}',
              style: const pw.TextStyle(
                color: _ink,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Text(
            card.studentName,
            style: const pw.TextStyle(color: _muted, fontSize: 9),
          ),
        ],
      ),
    );
  }

  pw.Widget _footer(pw.Context ctx) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 1.2, color: _ink),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Nivra · Boletín generado automáticamente',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
            pw.Text(
              'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: const pw.TextStyle(
                fontSize: 8,
                color: _accentDeep,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
