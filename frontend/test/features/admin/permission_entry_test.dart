import 'package:educa360/core/routing/route_paths.dart';
import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/admin/data/admin_backend_repository.dart';
import 'package:educa360/features/admin/data/school_directory.dart';
import 'package:educa360/features/admin/presentation/screens/admin_roles_screen.dart';
import 'package:educa360/features/admin/presentation/widgets/person_form.dart';
import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/domain/auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:educa360/shared/models/app_role.dart';
import 'package:educa360/shared/models/app_user.dart';
import 'package:educa360/shared/models/institution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _AdminAuth extends MockAuthRepository {
  @override
  Future<AuthSession?> currentSession() async => const AuthSession(
        user: AppUser(
            id: '1',
            institutionId: 2,
            email: 'admin@invalid.test',
            fullName: 'Admin',
            roles: [AppRole.admin],
            activeRole: AppRole.admin,),
        institution: Institution(id: 2, code: 'TEST', name: 'Test'),
      );
}

GoRouter _router(Widget home) => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => home),
      GoRoute(
          path: Routes.adminAccess,
          builder: (_, state) => Scaffold(
                body: Text(
                    'Permisos: ${state.uri.queryParameters['search'] ?? 'todos'}',),
              ),),
    ],);

Widget _app(GoRouter router) => ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_AdminAuth()),
        adminBackendRepositoryProvider.overrideWithValue(null),
      ],
      child:
          MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    );

void main() {
  testWidgets(
      'Roles y perfiles exposes Editar permisos and opens access management',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _router(const AdminRolesScreen());
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Editar permisos'));
    await tester.pumpAndSettle();
    expect(find.text('Permisos: todos'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  for (final role in [AppRole.student, AppRole.parent, AppRole.teacher]) {
    testWidgets(
        'profile permission shortcut closes the $role sheet and opens the correct search',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final person = Person(
          id: 'profile-42',
          name: 'Ana Gómez',
          role: role,
          email: 'ana@invalid.test',);
      final router = _router(Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () => showPersonSheet(context,
                        existing: person, pickRole: true,),
                    child: const Text('Abrir perfil'),
                  ),),),);
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir perfil'));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Editar permisos');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(
          find.text(
              'Permisos: ${role == AppRole.teacher ? 'todos' : person.name}',),
          findsOneWidget,);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
  }
}
