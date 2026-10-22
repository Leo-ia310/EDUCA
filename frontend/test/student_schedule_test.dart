import 'dart:async';

import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/core/widgets/skeleton.dart';
import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/domain/auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:educa360/features/dashboard/presentation/widgets/home_schedule_section.dart';
import 'package:educa360/features/schedule/data/schedule_mock.dart';
import 'package:educa360/features/schedule/presentation/screens/schedule_screen.dart';
import 'package:educa360/features/schedule/providers.dart';
import 'package:educa360/shared/models/app_role.dart';
import 'package:educa360/shared/models/app_user.dart';
import 'package:educa360/shared/models/institution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _session = AuthSession(
  user: AppUser(
    id: 'real-student',
    institutionId: 7,
    email: 'fixture@example.com',
    fullName: 'Fixture',
    roles: [AppRole.student],
    activeRole: AppRole.student,
  ),
  institution: Institution(id: 7, code: 'FIXTURE', name: 'Fixture'),
);

class _Auth extends MockAuthRepository {
  _Auth(this.session);
  final AuthSession? session;
  @override
  Future<AuthSession?> currentSession() async => session;
  @override
  Future<void> sendPasswordReset(
    String email, {
    Institution? institution,
  }) async {}
  @override
  Future<void> signOut() async {}
}

class _Api implements BackendApiClient {
  dynamic response = {'schedules': <dynamic>[]};
  bool fail = false;
  final requests = <Map<String, dynamic>>[];
  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    requests.add({
      'path': path,
      'query': queryParameters,
      'authenticated': authenticated,
    });
    if (fail) {
      throw StateError('API no disponible');
    }
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _container(
  _Api? api, {
  AuthSession? session = _session,
  bool listen = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      scheduleDemoEnabledProvider.overrideWithValue(false),
      backendApiClientProvider.overrideWithValue(api),
      authRepositoryProvider.overrideWithValue(_Auth(session)),
    ],
  );
  addTearDown(container.dispose);
  container.read(authControllerProvider);
  await Future<void>.delayed(Duration.zero);
  if (listen) container.listen(weeklySlotsProvider, (_, __) {});
  return container;
}

Future<void> _mount(
  WidgetTester tester,
  Future<Map<int, List<ClassSlot>>> Function() load, {
  bool detail = false,
}) async {
  final router = GoRouter(
    initialLocation: '/schedule',
    routes: [
      GoRoute(
        path: '/schedule',
        builder: (_, __) => detail
            ? const ScheduleScreen()
            : const Scaffold(
                body: SingleChildScrollView(child: HomeScheduleSection()),
              ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weeklySlotsProvider.overrideWith((ref) => load()),
        authRepositoryProvider.overrideWithValue(_Auth(_session)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
}

void main() {
  test('role changes reload timetable and logout cannot return retained data',
      () async {
    final api = _Api();
    final container = await _container(api);
    await container.read(weeklySlotsProvider.future);
    container
        .read(authControllerProvider.notifier)
        .setActiveRole(AppRole.teacher);
    await container.read(weeklySlotsProvider.future);
    expect(api.requests, hasLength(2));
    await container.read(authControllerProvider.notifier).signOut();
    await expectLater(
        container.read(weeklySlotsProvider.future), throwsStateError,);
    expect(api.requests, hasLength(2));
  });
  test('three route visits reuse one timetable request', () async {
    final api = _Api();
    final container = await _container(api, listen: false);
    for (var visit = 0; visit < 3; visit++) {
      final subscription = container.listen(weeklySlotsProvider, (_, __) {});
      await container.read(weeklySlotsProvider.future);
      subscription.close();
      await container.pump();
    }
    expect(api.requests, hasLength(1));
  });
  test('demo examples are disabled by default even without credentials', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(scheduleDemoEnabledProvider), isFalse);
  });
  test('empty real API stays empty and uses authenticated mine endpoint',
      () async {
    final api = _Api();
    final container = await _container(api);
    expect(await container.read(weeklySlotsProvider.future), isEmpty);
    expect(api.requests.single, {
      'path': '/schedules/mine',
      'query': <String, dynamic>{},
      'authenticated': true,
    });
  });
  test(
      'only returned classes appear and auth loading changes do not reload them',
      () async {
    final api = _Api()
      ..response = {
        'schedules': [
          {
            'weekdayIndex': 0,
            'kind': 'class',
            'subject': 'Álgebra asignada',
            'startTime': '08:00',
            'endTime': '09:00',
          },
        ],
      };
    final container = await _container(api);
    final weekly = await container.read(weeklySlotsProvider.future);
    expect(
      weekly.values.expand((v) => v).map((s) => s.subject),
      ['Álgebra asignada'],
    );
    await container
        .read(authControllerProvider.notifier)
        .sendPasswordReset('fixture@example.com');
    await container.read(weeklySlotsProvider.future);
    expect(api.requests, hasLength(1));
  });
  test('missing API/session and backend errors never fall back to examples',
      () async {
    final missingApi = await _container(null);
    await expectLater(
      missingApi.read(weeklySlotsProvider.future),
      throwsStateError,
    );
    final api = _Api();
    final missingSession = await _container(api, session: null);
    await expectLater(
      missingSession.read(weeklySlotsProvider.future),
      throwsStateError,
    );
    expect(api.requests, isEmpty);
    final failed = await _container(_Api()..fail = true);
    await expectLater(
      failed.read(weeklySlotsProvider.future),
      throwsStateError,
    );
  });
  test('malformed API response is an error instead of an empty timetable',
      () async {
    final container = await _container(_Api()..response = {'unexpected': []});
    await expectLater(
      container.read(weeklySlotsProvider.future),
      throwsStateError,
    );
  });
  testWidgets(
      'home distinguishes loading, no schedule and API failure with retry',
      (tester) async {
    final request = Completer<Map<int, List<ClassSlot>>>();
    var calls = 0;
    await _mount(tester, () {
      calls++;
      return calls == 1 ? request.future : Future.value({});
    });
    expect(find.byType(Skeleton), findsOneWidget);
    expect(find.text('No tienes horario asignado'), findsNothing);
    request.completeError(StateError('API no disponible'));
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudo cargar tu horario. Intenta nuevamente.'),
      findsOneWidget,
    );
    expect(find.text('No tienes horario asignado'), findsNothing);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('No tienes horario asignado'), findsOneWidget);
  });
  testWidgets('detail shows no assigned schedule and keeps errors separate',
      (tester) async {
    var calls = 0;
    await _mount(
      tester,
      () async {
        calls++;
        if (calls == 1) {
          throw StateError('API no disponible');
        }
        return {};
      },
      detail: true,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudo cargar el horario. Intenta nuevamente.'),
      findsOneWidget,
    );
    expect(find.text('Día libre'), findsNothing);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('No tienes horario asignado'), findsOneWidget);
    expect(find.text('Día libre'), findsNothing);
  });
}
