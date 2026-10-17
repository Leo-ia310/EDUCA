import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/core/widgets/brutal.dart';
import 'package:educa360/features/admin/data/admin_backend_repository.dart';
import 'package:educa360/features/admin/data/admin_profile.dart';
import 'package:educa360/features/admin/data/school_directory.dart';
import 'package:educa360/features/admin/presentation/screens/admin_roles_screen.dart';
import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/domain/auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:educa360/shared/models/app_role.dart';
import 'package:educa360/shared/models/app_user.dart';
import 'package:educa360/shared/models/institution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends MockAuthRepository {
  @override
  Future<AuthSession?> currentSession() async => const AuthSession(
        user: AppUser(
            id: '1',
            institutionId: 2,
            email: 'admin@example.com',
            fullName: 'Admin',
            roles: [AppRole.admin],
            activeRole: AppRole.admin,),
        institution: Institution(id: 2, code: 'TEST', name: 'Test'),
      );
}

class _Profiles implements AdminBackendRepository {
  final writes = <JsonMap>[];
  String? error;
  @override
  Future<AdminProfile> createProfile(JsonMap payload) async {
    writes.add(payload);
    if (error != null) throw StateError(error!);
    return AdminProfile(
        id: 'new',
        fullName: payload['fullName'] as String,
        email: payload['email'] as String,
        roleCode: payload['roleCode'] as String,
        permissions: List<String>.from(payload['permissions'] as List),);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(AdminBackendRepository repo, {bool failedList = false}) =>
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_Auth()),
        adminBackendRepositoryProvider.overrideWithValue(repo),
        adminSchoolDirectoryProvider
            .overrideWith((ref) async => const SchoolDirectory()),
        adminProfilesProvider.overrideWith((ref) async {
          if (failedList) throw StateError('No se pudo actualizar la lista');
          return <AdminProfile>[];
        }),
      ],
      child: MaterialApp(
          theme: AppTheme.lightTheme, home: const AdminRolesScreen(),),
    );

Future<void> _open(WidgetTester tester, String role) async {
  await tester.tap(find.text('Nuevo perfil'));
  await tester.pumpAndSettle();
  expect(find.text('Seleccionar rol'), findsOneWidget);
  expect(find.text('Supervisor / Coordinador'), findsOneWidget);
  expect(
      find.text('Administrador'), findsNWidgets(2),); // Role card and selector.
  await tester.tap(find.widgetWithText(ListTile, role));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(
      fields.at(1), 'Nombre perfil',); // Search remains behind sheet.
  await tester.enterText(fields.at(2), 'new@example.com');
  await tester.enterText(fields.at(4), 'StrongPassword123!');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Crear perfil'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Crear perfil'));
  await tester.pumpAndSettle();
}

void main() {
  for (final (code, label) in [
    ('admin', 'Administrador'),
    ('coordinator', 'Supervisor / Coordinador'),
  ]) {
    testWidgets('Nuevo perfil selects $code and submits its permissions',
        (tester) async {
      final repo = _Profiles();
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      await _open(tester, label);
      expect(
          tester
              .widget<BrutalPill>(find.widgetWithText(BrutalPill, label))
              .selected,
          isTrue,);
      await _submit(tester);
      expect(repo.writes.single['roleCode'], code);
      expect(repo.writes.single['permissions'], ['dashboard.view']);
      expect(find.text('Perfil creado correctamente'), findsOneWidget);
      expect(find.text('Crear perfil'), findsNothing);
    });
  }
  testWidgets('backend rejection stays visible without closing the form',
      (tester) async {
    final repo = _Profiles()..error = 'El correo ya está registrado.';
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    await _open(tester, 'Administrador');
    await _submit(tester);
    expect(find.text('El correo ya está registrado.'), findsOneWidget);
    expect(find.text('Crear perfil'), findsOneWidget);
    expect(find.text('Perfil creado correctamente'), findsNothing);
  });
  testWidgets('a list failure does not turn a successful save into an error',
      (tester) async {
    final repo = _Profiles();
    await tester.pumpWidget(_app(repo, failedList: true));
    await tester.pumpAndSettle();
    await _open(tester, 'Supervisor / Coordinador');
    await _submit(tester);
    expect(repo.writes, hasLength(1));
    expect(find.text('Perfil creado correctamente'), findsOneWidget);
    expect(find.text('Crear perfil'), findsNothing);
  });
}
