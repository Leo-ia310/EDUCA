import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/assignments/presentation/widgets/originality_card.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';

class TestAuthController extends StateNotifier<AuthState>
    implements AuthController {
  TestAuthController() : super(const AuthState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ReportApi implements BackendApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  int calls = 0;
  bool deny = false;
  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls++;
    if (deny) throw BackendApiException('Acceso revocado', statusCode: 403);
    return {
      'documents': [
        {
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
            'fragments': [
              {'text': 'evidencia protegida'},
            ],
            'sourceFragments': [],
          },
        }
      ],
      'notice':
          'Este resultado es orientativo; una coincidencia textual no demuestra plagio.',
    };
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  testWidgets(
      'lazy report shows one source, preserves content during refresh and clears on denial',
      (tester) async {
    final api = ReportApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendApiClientProvider.overrideWithValue(api),
          authControllerProvider.overrideWith((ref) => TestAuthController()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: OriginalityButton(submissionId: '5')),
        ),
      ),
    );
    expect(api.calls, 0);
    await tester.tap(find.text('Coincidencias textuales'));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(find.text('98.0 % de coincidencia textual máxima'), findsOneWidget);
    expect(find.text('Fuente: fuente.txt · Ana'), findsOneWidget);
    expect(find.textContaining('no demuestra plagio'), findsOneWidget);
    await tester.tap(find.text('Ver fragmentos coincidentes'));
    await tester.pumpAndSettle();
    expect(find.text('evidencia protegida'), findsOneWidget);
    api.deny = true;
    await tester.tap(find.byTooltip('Actualizar'));
    await tester.pumpAndSettle();
    expect(find.text('Fuente: fuente.txt · Ana'), findsNothing);
    expect(find.textContaining('No se pudo consultar'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('report fits a small dark screen with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendApiClientProvider.overrideWithValue(ReportApi()),
          authControllerProvider.overrideWith((ref) => TestAuthController()),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const Scaffold(body: OriginalityButton(submissionId: '5')),
        ),
      ),
    );
    await tester.tap(find.text('Coincidencias textuales'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Fuente: fuente.txt · Ana'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
