import 'dart:typed_data';

import 'package:educa360/features/grades/domain/entities.dart';
import 'package:educa360/features/payments/domain/entities.dart';
import 'package:educa360/features/reports/domain/pdf_style.dart';
import 'package:educa360/features/reports/domain/receipt_pdf_service.dart';
import 'package:educa360/features/reports/domain/report_pdf_service.dart';
import 'package:educa360/shared/models/institution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

ReportCard _card(int subjects) => ReportCard(
      studentId: 1,
      studentName: 'Camila Ortega',
      institutionName: 'Big School',
      gradeLevel: '1er Grado A',
      periodName: 'III Trimestre',
      periodStart: DateTime(2026, 8),
      periodEnd: DateTime(2026, 10, 30),
      lines: [
        for (var i = 0; i < subjects; i++)
          ReportCardLine(
            subjectName: 'Materia $i',
            teacherName: 'Docente $i',
            finalScore: 50.0 + i,
            qualitativeLabel: i.isEven ? 'Bueno' : null,
            passed: i > 10,
            evaluationCount: i == 3 ? 0 : 2,
          ),
      ],
      overallAverage: 70.5,
      overallLabel: 'Bueno',
      attendancePct: 95,
      rank: 2,
      totalPeers: 20,
    );

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('genera el boletín sin recursos opcionales (sin red ni logo)', () async {
    final bytes = await const ReportPdfService().buildReportCard(_card(6));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('un boletín con muchas materias se parte en varias páginas', () async {
    final bytes = await const ReportPdfService().buildReportCard(_card(40));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('si falla la carga de recursos, usa la tipografía estándar', () async {
    final service =
        ReportPdfService(loadAssets: ({logoUrl}) async => throw Exception());
    final bytes = await service.buildReportCard(_card(3));
    expect(bytes, isNotEmpty);
  });

  test('un logo del colegio ilegible no rompe el boletín (usa el de respaldo)',
      () async {
    final service = ReportPdfService(
      loadAssets: ({logoUrl}) async => PdfAssets(
        schoolLogo: Uint8List.fromList([1, 2, 3]),
      ),
    );
    final bytes = await service.buildReportCard(
      _card(3),
      branding:
          const PdfBranding(name: 'Colegio Real', logoUrl: 'https://x/y.png'),
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('el recibo se genera con y sin grado conocido', () async {
    final charge = Charge(
      id: 'c1',
      studentId: 1,
      studentName: 'Camila',
      conceptId: 'k1',
      conceptName: 'Mensualidad',
      description: 'Mensualidad',
      amount: 1500,
      discount: 0,
      lateFee: 0,
      dueDate: DateTime(2026, 10, 10),
      currencyCode: 'NIO',
      status: ChargeStatus.paid,
      academicYear: '2026',
    );
    final payment = Payment(
      id: 'p1',
      uuid: 'u1',
      chargeId: 'c1',
      chargeConcept: 'Mensualidad',
      studentName: 'Camila',
      method: PaymentMethod.cash,
      amount: 1500,
      currencyCode: 'NIO',
      status: PaymentStatus.paid,
      paidAt: DateTime(2026, 10, 12),
      receiptNumber: 'REC-1',
    );
    for (final grade in [null, '1er Grado A']) {
      final bytes = await const ReceiptPdfService().buildReceipt(
        Receipt(
          payment: payment,
          charge: charge,
          institutionName: 'Colegio Real',
          payerName: 'Padre',
          issuedAt: DateTime(2026, 10, 12),
          gradeLevel: grade,
        ),
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    }
  });

  test('Institution.displayName prefiere el nombre comercial', () {
    const base = Institution(id: 1, code: 'X', name: 'Colegio S.A.');
    expect(base.displayName, 'Colegio S.A.');
    const commercial = Institution(
      id: 1,
      code: 'X',
      name: 'Colegio S.A.',
      commercialName: '  Colegio Real ',
    );
    expect(commercial.displayName, 'Colegio Real');
    const blank = Institution(
      id: 1,
      code: 'X',
      name: 'Colegio S.A.',
      commercialName: '   ',
    );
    expect(blank.displayName, 'Colegio S.A.');
  });
}
