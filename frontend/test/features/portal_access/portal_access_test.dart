import 'dart:async';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/domain/auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:educa360/features/portal_access/access_widgets.dart';
import 'package:educa360/features/portal_access/admin_access_screen.dart';
import 'package:educa360/features/portal_access/portal_grades_screen.dart';
import 'package:educa360/features/portal_access/providers.dart';
import 'package:educa360/shared/models/app_role.dart';
import 'package:educa360/shared/models/app_user.dart';
import 'package:educa360/shared/models/institution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PortalAccess _access({bool grades = true}) => PortalAccess.fromJson({
      'permissions': {
        for (final code in portalPermissionLabels.keys)
          code: code != 'grades.view' || grades,
      },
      'students': [
        {
          'studentId': 10,
          'name': 'Ana',
          'annualVisible': false,
          'periods': [
            {'id': 1, 'name': 'I Trimestre', 'visible': true},
            {'id': 2, 'name': 'II Trimestre', 'visible': false},
          ],
        }
      ],
    });

class _Auth extends MockAuthRepository {
  @override
  Future<AuthSession?> currentSession() async => const AuthSession(
        institution: Institution(id: 2, code: 'TEST', name: 'Test'),
        user: AppUser(
          id: '7',
          institutionId: 2,
          email: 'portal@invalid.test',
          fullName: 'Portal',
          roles: [AppRole.parent],
          activeRole: AppRole.parent,
        ),
      );
}

class _Api implements BackendApiClient {
  final writes = <Map<String, dynamic>>[];
  final reads = <Map<String, dynamic>?>[];
  final userReads = <int>[];
  bool failUserSave = false;
  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    expect(path, '/portal-access/config');
    if (data?['action'] == 'save_user_permissions' && failUserSave) {
      throw StateError('offline');
    }
    writes.add(data!);
    return {};
  }

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final userPath =
        RegExp(r'^/portal-access/users/(\d+)/permissions$').firstMatch(path);
    if (userPath != null) {
      final id = int.parse(userPath.group(1)!);
      userReads.add(id);
      return {
        'userId': id,
        'permissions': {
          for (final code in portalPermissionLabels.keys)
            code: code != 'grades.view',
        },
        'overrides': {'grades.view': false},
      };
    }
    expect(path, '/portal-access/grades');
    reads.add(queryParameters);
    return {
      'grades': [
        {
          'score': 86,
          'evaluations': {
            'max_score': 100,
            'title': 'Examen permitido',
            'classes': {
              'subjects': {'name': 'Matemáticas'},
            },
          },
        }
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _config = <String, dynamic>{
  'permissionRules': <dynamic>[],
  'visibilityRules': <dynamic>[],
  'users': [
    {'id': 7, 'name': 'Padre de Ana'},
  ],
  'groups': [
    {'id': 3, 'name': '10mo'},
  ],
  'students': [
    {'id': 10, 'name': 'Ana'},
  ],
  'periods': [
    {'id': 2, 'name': 'II Trimestre'},
  ],
};
Widget _app(
  Widget child, {
  _Api? api,
  PortalAccess? access,
  Map<String, dynamic>? config,
}) =>
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_Auth()),
        portalAccessLoaderProvider
            .overrideWithValue(() async => access ?? _access()),
        portalAccessConfigProvider
            .overrideWith((ref) async => config ?? _config),
        if (api != null) backendApiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, home: child),
    );

void main() {
  testWidgets(
      'user search finds any account and pencil opens its own permissions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _Api();
    final config = {
      ..._config,
      'users': [
        for (var i = 0; i < 1000; i++)
          {
            'id': 100 + i,
            'name': i == 999 ? 'José Pérez' : 'Alumno $i',
            'roles': ['student'],
          },
      ],
    };
    await tester
        .pumpWidget(_app(const AdminAccessScreen(), api: api, config: config));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar usuarios'),
      'jose perez',
    );
    await tester.pumpAndSettle();
    expect(find.text('José Pérez'), findsOneWidget);
    expect(find.text('1 usuario'), findsOneWidget);
    await tester.tap(find.byTooltip('Editar permisos de José Pérez'));
    await tester.pumpAndSettle();
    expect(find.text('Editar permisos'), findsOneWidget);
    expect(api.userReads, [1099]);
    expect(
      find.byType(SwitchListTile),
      findsNWidgets(portalPermissionLabels.length),
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Ver notas'),
          )
          .value,
      false,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Ver boletín'),
          )
          .value,
      true,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'individual switches save mixed states only for the selected user and keep edits on failure',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _Api()..failUserSave = true;
    await tester.pumpWidget(_app(const AdminAccessScreen(), api: api));
    await tester.pumpAndSettle();
    final pencil = find.byTooltip('Editar permisos de Padre de Ana');
    await tester.ensureVisible(pencil);
    await tester.tap(pencil);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Guardar permisos'),
          )
          .onPressed,
      isNull,
    );
    for (final label in ['Ver notas', 'Descargar boletín']) {
      final toggle = find.widgetWithText(SwitchListTile, label);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Guardar permisos'));
    await tester.pumpAndSettle();
    expect(find.text('Editar permisos'), findsOneWidget);
    expect(
      find.text(
        'No se pudieron guardar los permisos. Puedes intentarlo de nuevo.',
      ),
      findsOneWidget,
    );
    api.failUserSave = false;
    await tester.tap(find.text('Guardar permisos'));
    await tester.pumpAndSettle();
    expect(api.writes.single, {
      'action': 'save_user_permissions',
      'userId': 7,
      'permissions': [
        {'permission': 'grades.view', 'allowed': true},
        {'permission': 'reports.download', 'allowed': false},
      ],
    });
    expect(find.text('Editar permisos'), findsNothing);
    expect(find.text('Permisos del usuario actualizados.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('mobile permission selection can be cleared without saving rules',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _Api();
    await tester.pumpWidget(_app(const AdminAccessScreen(), api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Permisos por rol o usuario'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar'))
          .onPressed,
      isNull,
    );
    for (final label in ['Ver boletín', 'Descargar boletín']) {
      final checkbox = find.widgetWithText(CheckboxListTile, label);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
    }
    expect(find.text('Guardar 2 permisos'), findsOneWidget);
    await tester.ensureVisible(find.text('Limpiar selección'));
    await tester.tap(find.text('Limpiar selección'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'idle access does not poll and unchanged background updates do not reload consumers',
      (tester) async {
    final events = StreamController<void>();
    var loads = 0;
    var current = _access();
    final container = ProviderContainer(
      overrides: [
        portalAccessLoaderProvider.overrideWithValue(() async {
          loads++;
          return current;
        }),
        portalAccessChangesProvider.overrideWith((ref) => events.stream),
      ],
    );
    final states = <AsyncValue<PortalAccess>>[];
    final subscription = container.listen(
      portalAccessProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    await tester.pump();
    await container.read(portalAccessProvider.future);
    await tester.pump();
    final initialStates = states.length;
    expect(loads, 1);
    await tester.pump(const Duration(minutes: 10));
    expect(loads, 1, reason: 'No permission requests while the user is idle');
    events.add(null);
    await tester.pump();
    await tester.pump();
    expect(loads, 2);
    expect(
      states.length,
      initialStates,
      reason: 'Identical access keeps the same data state',
    );
    current = _access(grades: false);
    events.add(null);
    await tester.pump();
    await tester.pump();
    expect(container.read(portalCanProvider('grades.view')), false);
    expect(
      states.skip(initialStates).every((s) => !s.isLoading),
      true,
      reason: 'A background update never replaces the screen with loading',
    );
    subscription.close();
    container.dispose();
    unawaited(events.close());
    await tester.pump();
  });
  testWidgets('admin can find one student among 1000 by typing without accents',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _Api();
    final config = {
      ..._config,
      'students': [
        for (var i = 0; i < 1000; i++)
          {
            'id': 100 + i,
            'name': i == 999 ? 'José Pérez 0999' : 'Estudiante $i',
          },
      ],
    };
    await tester
        .pumpWidget(_app(const AdminAccessScreen(), api: api, config: config));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visibilidad de notas').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estudiante').last);
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(TextFormField, 'Seleccionar destinatario'));
    await tester.pumpAndSettle();
    expect(
      find.text('Mostrando 50 de 1000. Escribe para filtrar.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre del destinatario'),
      'jose perez 0999',
    );
    await tester.pumpAndSettle();
    expect(find.text('1 resultado'), findsOneWidget);
    await tester.tap(find.text('José Pérez 0999'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(api.writes.single['studentId'], 1099);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('a hidden period blocks annual summaries without hiding other periods',
      () {
    final access = _access();
    expect(access.gradeVisible(10, '1'), true);
    expect(access.gradeVisible(10, '2'), false);
    expect(access.gradeVisible(10, null), false);
    expect(access.gradeVisible(99, '1'), false);
    expect(access.annualGradesVisible, false);
    expect(access.anyGradesVisible, true);
    expect(_access(grades: false).gradeVisible(10, '1'), false);
    expect(PortalAccess.unrestricted().gradeVisible(99, '2'), true);
  });
  testWidgets(
      'a blocked deep link shows restriction and never builds the data screen',
      (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      _app(
        PortalRouteGate(
          path: '/grades',
          onHome: () {},
          child: Builder(
            builder: (_) {
              builds++;
              return const Text('Datos privados');
            },
          ),
        ),
        access: _access(grades: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Acceso restringido'), findsWidgets);
    expect(find.text('Datos privados'), findsNothing);
    // Auth finishes before the protected route may be displayed.
    expect(builds, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'a hidden annual report keeps the period selector usable and does not request hidden grades',
      (tester) async {
    final api = _Api();
    await tester.pumpWidget(_app(const PortalGradesScreen(), api: api));
    await tester.pumpAndSettle();
    expect(find.text('Acceso restringido'), findsOneWidget);
    expect(api.reads, isEmpty);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I Trimestre').last);
    await tester.pumpAndSettle();
    expect(find.text('Examen permitido'), findsOneWidget);
    expect(api.reads.single, {'studentId': 10, 'periodId': '1'});
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('II Trimestre · oculto').last);
    await tester.pumpAndSettle();
    expect(find.text('Acceso restringido'), findsOneWidget);
    expect(find.text('Examen permitido'), findsNothing);
    expect(api.reads, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('admin disables multiple parent permissions in one save',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _Api();
    await tester.pumpWidget(_app(const AdminAccessScreen(), api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Permisos por rol o usuario'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuario específico: padre o alumno').last);
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(TextFormField, 'Seleccionar destinatario'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre del destinatario'),
      'Padre de Ana',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Padre de Ana').last);
    await tester.pumpAndSettle();
    for (final label in ['Ver notas', 'Ver boletín', 'Descargar boletín']) {
      final checkbox = find.widgetWithText(CheckboxListTile, label);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Guardar 3 permisos'));
    await tester.pumpAndSettle();
    expect(api.writes.single, {
      'action': 'save_permissions',
      'scope': 'user',
      'allowed': false,
      'userId': 7,
      'permissions': ['grades.view', 'reports.view', 'reports.download'],
    });
    expect(find.text('Accesos actualizados.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('admin can hide a group only during a selected trimester',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _Api();
    await tester.pumpWidget(_app(const AdminAccessScreen(), api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visibilidad de notas').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grupo').last);
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(TextFormField, 'Seleccionar destinatario'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10mo').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('II Trimestre').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(api.writes.single, {
      'action': 'save_visibility',
      'scope': 'group',
      'allowed': false,
      'groupId': 3,
      'periodId': 2,
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
