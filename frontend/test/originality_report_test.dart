import 'package:flutter_test/flutter_test.dart';
import 'package:educa360/features/assignments/data/originality_report.dart';

Map<String, dynamic> document({
  String state = 'completed',
  bool compared = false,
  double? coverage,
}) =>
    {
      'name': 'ensayo.txt',
      'state': state,
      'preliminary': false,
      'compared': compared,
      'submittedAt': '2026-10-23T10:00:00Z',
      'processedAt': null,
      'topMatch': coverage == null
          ? null
          : {
              'coverage': coverage,
              'sourceName': 'fuente.txt',
              'sourceStudent': 'Alumno',
              'sourceSubmittedAt': '2026-10-23T09:00:00Z',
              'binaryIdentical': false,
              'textIdentical': false,
              'fragments': [
                {'text': 'Fragmento'},
              ],
              'sourceFragments': [],
            },
    };
void main() {
  test('no percentage before an actual completed comparison', () {
    expect(OriginalityDocument.fromJson(document()).coverage, isNull);
    expect(
      OriginalityDocument.fromJson(document(state: 'queued', compared: true))
          .coverage,
      isNull,
    );
    expect(OriginalityDocument.fromJson(document(compared: true)).coverage, 0);
    expect(
      OriginalityDocument.fromJson(document(compared: true, coverage: 98))
          .coverage,
      98,
    );
  });
  test('state, UTC dates, fragments and polling retain their meaning', () {
    final doc = OriginalityDocument.fromJson(document(state: 'processing'));
    expect(doc.pending, isTrue);
    expect(doc.submittedAt.isUtc, isTrue);
    expect(
      OriginalityDocument.fromJson(document(state: 'failed')).label,
      contains('entrega sigue válida'),
    );
    final match =
        OriginalityDocument.fromJson(document(compared: true, coverage: 100))
            .match!;
    expect(match.fragments, ['Fragmento']);
    expect(
      OriginalityReport.fromJson({'documents': [], 'notice': 'Orientativo'})
          .pending,
      isTrue,
    );
  });
}
