import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../payments/domain/entities.dart';
import '../../payments/presentation/widgets/money_text.dart';
import 'pdf_style.dart';

/// Genera el PDF de recibo de pago (A5 vertical: cabe mejor al compartir por
/// WhatsApp o correo) con el mismo lenguaje visual que el boletín y la app.
class ReceiptPdfService {
  const ReceiptPdfService({this.loadAssets});

  final PdfAssetsLoader? loadAssets;

  /// [branding] trae el nombre a mostrar y el logo del colegio que emite el
  /// recibo; sin él se usa el nombre que viene en [r] y el logo de Nivra.
  Future<Uint8List> buildReceipt(Receipt r, {PdfBranding? branding}) async {
    PdfAssets? assets;
    try {
      assets = await loadAssets?.call(logoUrl: branding?.logoUrl);
    } catch (_) {
      assets = null; // sin red/recursos: tipografía estándar
    }
    final school = branding?.name.trim().isNotEmpty ?? false
        ? branding!.name.trim()
        : r.institutionName;

    final doc = pw.Document(
      title: 'Recibo ${r.payment.receiptNumber}',
      author: school,
      creator: 'Nivra',
      theme: assets?.theme,
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.fromLTRB(26, 26, 26, 22),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _hero(r, school, assets?.logo),
            pw.SizedBox(height: 14),
            _amount(r),
            pw.SizedBox(height: 14),
            _details(r),
            pw.SizedBox(height: 14),
            _note(),
            pw.Spacer(),
            PdfStyle.footer('Nivra · Recibo ${r.payment.receiptNumber}'),
          ],
        ),
      ),
    );

    return doc.save();
  }

  pw.Widget _hero(Receipt r, String school, pw.MemoryImage? logo) {
    return PdfStyle.card(
      fill: PdfStyle.accent,
      radius: 14,
      shadow: 4,
      padding: const pw.EdgeInsets.all(13),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          PdfStyle.logoBox(logo, size: 40),
          pw.SizedBox(width: 11),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'NIVRA · RECIBO OFICIAL DE PAGO',
                  style: const pw.TextStyle(
                    color: PdfStyle.accentSoft,
                    fontSize: 6.5,
                    letterSpacing: 1,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  school,
                  style: const pw.TextStyle(
                    color: PdfStyle.white,
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 8),
          PdfStyle.chip(
            'N.º ${r.payment.receiptNumber}',
            PdfStyle.white,
            PdfStyle.ink,
          ),
        ],
      ),
    );
  }

  pw.Widget _amount(Receipt r) {
    final issued = DateFormat("d 'de' MMMM 'de' y, HH:mm", 'es');
    return PdfStyle.card(
      fill: PdfStyle.successSoft,
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'TOTAL PAGADO',
                  style: const pw.TextStyle(
                    color: PdfStyle.success,
                    fontSize: 7,
                    letterSpacing: 1,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  Money.format(r.payment.amount, r.payment.currencyCode),
                  style: const pw.TextStyle(
                    color: PdfStyle.ink,
                    fontSize: 26,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Emitido ${issued.format(r.issuedAt)}',
                  style: const pw.TextStyle(
                    color: PdfStyle.muted,
                    fontSize: 8.5,
                  ),
                ),
              ],
            ),
          ),
          PdfStyle.chip('Pagado', PdfStyle.white, PdfStyle.success),
        ],
      ),
    );
  }

  pw.Widget _details(Receipt r) {
    final rows = <(String, String)>[
      ('Concepto', r.charge.conceptName),
      ('Estudiante', r.payment.studentName),
      ('Padre / Tutor', r.payerName),
      if (r.gradeLevel != null && r.gradeLevel!.trim().isNotEmpty)
        ('Grado', r.gradeLevel!),
      ('Método', r.payment.method.label),
      if (r.payment.reference != null) ('Referencia', r.payment.reference!),
      if (r.payment.gatewayName != null) ('Procesador', r.payment.gatewayName!),
    ];
    return PdfStyle.card(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: pw.Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              decoration: pw.BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : const pw.Border(
                        bottom: pw.BorderSide(
                          color: PdfStyle.line,
                          width: 0.8,
                        ),
                      ),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 92,
                    child: pw.Text(
                      rows[i].$1.toUpperCase(),
                      style: const pw.TextStyle(
                        color: PdfStyle.muted,
                        fontSize: 7,
                        letterSpacing: 0.8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      rows[i].$2,
                      style: const pw.TextStyle(
                        color: PdfStyle.ink,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _note() {
    return PdfStyle.card(
      fill: PdfStyle.sunSoft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: pw.Text(
        'Documento emitido electrónicamente por Nivra. Este recibo tiene '
        'validez como comprobante interno.',
        style: const pw.TextStyle(
          color: PdfStyle.ink,
          fontSize: 8.5,
          lineSpacing: 1.4,
        ),
      ),
    );
  }
}
