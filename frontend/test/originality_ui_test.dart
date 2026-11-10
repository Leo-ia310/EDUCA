import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/assignments/data/originality_api.dart';
import 'package:educa360/features/assignments/data/originality_report.dart';
import 'package:educa360/features/assignments/data/originality_summary.dart';
import 'package:educa360/features/assignments/presentation/controllers/originality_controller.dart';
import 'package:educa360/features/assignments/presentation/widgets/originality_summary_card.dart';
import 'package:educa360/features/assignments/presentation/widgets/originality_widgets.dart';

class FakeApi implements OriginalityApi {
  int summaries = 0;
  int reports = 0;
  bool lastEvidence = false;
  bool deny = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<OriginalitySummary> summary(String assignmentId) async {
    summaries++;
    return OriginalitySummary.fromJson({
      'assignmentId': 7,
      'eligible': 4,
      'preliminary': true,
      'hasTemplate': false,
      'notice': originalityNotice,
      'items': [
        item(1, 'completed', compared: true, coverage: 98),
        item(2, 'completed', compared: true, coverage: 12),
        item(3, 'insufficient_text'),
        item(4, 'failed'),
      ],
    });
  }

  @override
  Future<OriginalityReport> report(
    String submissionId, {
    bool evidence = false,
  }) async {
    reports++;
    lastEvidence = evidence;
    if (deny) throw BackendApiException('Sin acceso', statusCode: 403);
    return OriginalityReport.fromJson({
      'notice': originalityNotice,
      'documents': [
        {
          'id': 1,
          'name': 'ensayo.txt',
          'state': 'completed',
          'preliminary': false,
          'compared': true,
          'submittedAt': '2026-10-23T10:00:00Z',
          'processedAt': '2026-10-23T10:01:00Z',
          'topMatch': {
            'coverage': 98.0,
            'sourceName': 'fuente.txt',
            'sourceStudent': 'Ana',
            'sourceSubmittedAt': '2026-10-23T09:00:00Z',
            'binaryIdentical': false,
            'textIdentical': false,
            'fragments': evidence
                ? [
                    {'text': 'evidencia protegida', 'start': 0, 'end': 19},
                  ]
                : null,
            'sourceFragments': evidence ? [] : null,
          },
        },
      ],
    });
  }
}

Map<String, dynamic> item(
  int id,
  String state, {
  bool compared = false,
  double? coverage,
}) =>
    {
      'submissionId': id,
      'studentId': id,
      'state': state,
      'compared': compared,
      'coverage': coverage,
      'binaryIdentical': false,
      'textIdentical': false,
      'submittedAt': '2026-10-23T10:00:00Z',
    };

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('summary: counts, bands and no percentage without a comparison', () {
    final s = OriginalitySummary.fromJson({
      'assignmentId': 7,
      'eligible': 4,
      'preliminary': false,
      'hasTemplate': true,
      'notice': 'x',
      'items': [
        item(1, 'completed', compared: true, coverage: 98),
        item(2, 'completed', compared: false),
        item(3, 'queued'),
        item(4, 'failed'),
      ],
    });
    expect(s.pendingCount, 1);
    expect(s.failedCount, 1);
    expect(s.analyzedCount, 2);
    expect(s.withPercentage, 1);
    expect(s.top!.submissionId, 1);
    expect(s.itemFor('2')!.shownCoverage, isNull);
    expect(s.bands[OriginalityBand.high], 1);
    expect(s.working, isTrue);
    expect(OriginalityBand.of(14.9), OriginalityBand.minimal);
    expect(OriginalityBand.of(40), OriginalityBand.moderate);
  });

  test(
      'report controller asks for evidence only on demand and clears on denial',
      () async {
    final api = FakeApi();
    final container = ProviderContainer(
      overrides: [originalityApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    const args = (assignmentId: '7', submissionId: '1');
    final sub = container.listen(originalityReportProvider(args), (_, __) {});
    await Future<void>.delayed(Duration.zero);
    expect(api.lastEvidence, isFalse);
    expect(sub.read().report!.documents.single.match!.hasEvidence, isFalse);
    await container
        .read(originalityReportProvider(args).notifier)
        .showEvidence();
    expect(api.lastEvidence, isTrue);
    expect(
      sub.read().report!.documents.single.match!.fragments.single.text,
      'evidencia protegida',
    );
    api.deny = true;
    await container.read(originalityReportProvider(args).notifier).load();
    expect(sub.read().denied, isTrue);
    expect(sub.read().report, isNull);
    expect(sub.read().evidence, isFalse);
  });

  testWidgets('summary card on a small dark screen with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [originalityApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: OriginalitySummaryCard(
                assignmentId: '7',
                canEditTemplate: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('3 de 4'), findsOneWidget);
    expect(find.text('98 %'), findsOneWidget);
    expect(find.textContaining('no demuestra plagio'), findsOneWidget);
    expect(find.text('Agregar plantilla de exclusión'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('row shows state without a percentage and never says copy',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Column(
            children: [
              OriginalityRow(
                assignmentId: '7',
                submissionId: '3',
                item: OriginalityItem.fromJson(item(3, 'insufficient_text')),
              ),
              OriginalityRow(
                assignmentId: '7',
                submissionId: '1',
                item: OriginalityItem.fromJson(
                  item(1, 'completed', compared: true, coverage: 37.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Texto insuficiente'), findsWidgets);
    expect(find.text('37.5 %'), findsOneWidget);
    expect(find.textContaining('copia'), findsNothing);
  });
}
