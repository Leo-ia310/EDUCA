import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../payments/domain/entities.dart';
import '../../payments/presentation/widgets/money_text.dart';

/// Genera el PDF de recibo de pago. Diseño A5 vertical (cabe mejor en
/// compartir por WhatsApp/correo). Reutiliza la paleta de marca lima.
class ReceiptPdfService {
  const ReceiptPdfService();

  Future<Uint8List> buildReceipt(Receipt r) async {
    final doc = pw.Document(
      title: 'Recibo ${r.payment.receiptNumber}',
    );
    final green = PdfColor.fromInt(0xFF9BE000);
    final dark = PdfColor.fromInt(0xFF1E2218);
    final muted = PdfColor.fromInt(0xFF5C6354);
    final surface = PdfColor.fromInt(0xFFF1F4E2);
    final divider = PdfColor.fromInt(0xFFE3E7D2);

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(r, green, dark, muted),
          pw.SizedBox(height: 16),
          _summary(r, dark, muted, surface),
          pw.SizedBox(height: 16),
          _detailRow('Concepto', r.charge.conceptName, dark, muted, divider),
          _detailRow('Estudiante', r.payment.studentName, dark, muted, divider),
          _detailRow('Padre / Tutor', r.payerName, dark, muted, divider),
          _detailRow('Grado', r.gradeLevel, dark, muted, divider),
          _detailRow('Método', r.payment.method.label, dark, muted, divider),
          if (r.payment.reference != null)
            _detailRow(
              'Referencia',
              r.payment.reference!,
              dark,
              muted,
              divider,
            ),
          if (r.payment.gatewayName != null)
            _detailRow(
              'Procesador',
              r.payment.gatewayName!,
              dark,
              muted,
              divider,
            ),
          pw.SizedBox(height: 12),
          pw.Divider(color: divider),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total pagado',
                  style: pw.TextStyle(
                      color: dark, fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                Money.format(r.payment.amount, r.payment.currencyCode),
                style: pw.TextStyle(
                    color: PdfColor.fromInt(0xFF15803D),
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          _footer(r, muted),
        ],
      ),
    ));

    return doc.save();
  }

  pw.Widget _header(
      Receipt r, PdfColor green, PdfColor dark, PdfColor muted) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 42,
          height: 42,
          decoration: pw.BoxDecoration(
            color: green,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          alignment: pw.Alignment.center,
          child: pw.Text('E360',
              style: pw.TextStyle(
                  color: dark, fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(r.institutionName,
                  style: pw.TextStyle(
                      color: dark,
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold)),
              pw.Text('Recibo oficial de pago',
                  style: pw.TextStyle(color: muted, fontSize: 10)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Recibo',
                style: pw.TextStyle(color: muted, fontSize: 8)),
            pw.Text(r.payment.receiptNumber,
                style: pw.TextStyle(
                    color: dark, fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  pw.Widget _summary(
      Receipt r, PdfColor dark, PdfColor muted, PdfColor surface) {
    final fmt = DateFormat("d 'de' MMMM 'de' y, HH:mm", 'es');
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: surface,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Emitido',
              style: pw.TextStyle(color: muted, fontSize: 9)),
          pw.Text(
            fmt.format(r.issuedAt),
            style: pw.TextStyle(
                color: dark, fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _detailRow(
      String k, String v, PdfColor dark, PdfColor muted, PdfColor divider) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      decoration: pw.BoxDecoration(
        border:
            pw.Border(bottom: pw.BorderSide(color: divider, width: 0.5)),
      ),
      child: pw.Row(
        children: [
          pw.SizedBox(
              width: 100,
              child: pw.Text(k,
                  style: pw.TextStyle(color: muted, fontSize: 9))),
          pw.Expanded(
            child: pw.Text(v,
                style: pw.TextStyle(
                    color: dark, fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  pw.Widget _footer(Receipt r, PdfColor muted) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Documento emitido electrónicamente por Educa360.',
            style: pw.TextStyle(color: muted, fontSize: 8)),
        pw.Text('Este recibo tiene validez como comprobante interno.',
            style: pw.TextStyle(color: muted, fontSize: 8)),
      ],
    );
  }
}
