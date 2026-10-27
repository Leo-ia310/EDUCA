import 'package:educa360/features/grades/domain/entities.dart';
import 'package:educa360/features/reports/domain/report_pdf_service.dart';
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
    final service = ReportPdfService(loadAssets: () async => throw Exception());
    final bytes = await service.buildReportCard(_card(3));
    expect(bytes, isNotEmpty);
  });
}
