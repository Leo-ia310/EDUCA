import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/core/routing/app_router.dart';
import 'package:educa360/core/routing/route_paths.dart';
import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/domain/auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:educa360/features/auth/presentation/screens/change_password_screen.dart';
import 'package:educa360/shared/models/institution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Auth extends MockAuthRepository {
  @override
  Future<AuthSession?> currentSession() async => null;
  @override
  Future<SignInResult> signIn({
    Institution? institution,
    required String emailOrUsername,
    required String password,
  }) async => const SignInResult.twoFactor(
    TwoFactorChallenge(id: 'fixture', method: 'totp'),
  );
}

class _Api implements BackendApiClient {
  final writes = <Map<String, dynamic>>[];
  String? error;
  @override
  Future<dynamic> post(String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    writes.add({'path': path, 'data': data, 'authenticated': authenticated});
    if (error != null) { throw StateError(error!); }
    return {'ok': true};
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(WidgetTester tester, _Api api, {String? token}) async {
  final router = GoRouter(initialLocation: '/form', routes: [
    GoRoute(path: '/form', builder: (_, __) => ChangePasswordScreen(recoveryToken: token),),
    GoRoute(path: Routes.login, builder: (_, __) => const Scaffold(body: Text('Login seguro')),),
    GoRoute(path: Routes.forgotPassword, builder: (_, __) => const Scaffold(body: Text('Solicitar recuperación')),),
  ],);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides: [
    authRepositoryProvider.overrideWithValue(_Auth()),
    backendApiClientProvider.overrideWithValue(api),
  ], child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router,),),);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Guardar cambios'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Guardar cambios'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('recovery submits anonymously and returns to login after success', (tester) async {
    final api = _Api();
    await _mount(tester, api, token: 'one-use-token');
    expect(find.text('Contraseña actual'), findsNothing);
    await tester.enterText(find.byType(TextFormField).at(0), 'NewPassword123!');
    await tester.enterText(find.byType(TextFormField).at(1), 'NewPassword123!');
    await _save(tester);
    expect(api.writes.single, {'path': '/auth/reset-password', 'data': {'tokenHash': 'one-use-token', 'newPassword': 'NewPassword123!'}, 'authenticated': false});
    expect(find.text('Login seguro'), findsOneWidget);
  });
  testWidgets('expired recovery displays the error and offers another link', (tester) async {
    final api = _Api()..error = 'El enlace es inválido, expiró o ya fue utilizado. Solicita uno nuevo.';
    await _mount(tester, api, token: 'expired');
    await tester.enterText(find.byType(TextFormField).at(0), 'NewPassword123!');
    await tester.enterText(find.byType(TextFormField).at(1), 'NewPassword123!');
    await _save(tester);
    expect(find.text(api.error!), findsOneWidget);
    expect(find.text('Login seguro'), findsNothing);
    expect(find.text('Solicitar otro enlace'), findsOneWidget);
  });
  testWidgets('missing link cannot submit a new password', (tester) async {
    final api = _Api();
    await _mount(tester, api, token: '');
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Solicitar nuevo enlace'), findsOneWidget);
    expect(api.writes, isEmpty);
  });
  testWidgets('signed-in change sends the current password and enforces 8 characters', (tester) async {
    final api = _Api();
    await _mount(tester, api);
    await tester.enterText(find.byType(TextFormField).at(0), 'OldPassword123!');
    await tester.enterText(find.byType(TextFormField).at(1), 'short');
    await tester.enterText(find.byType(TextFormField).at(2), 'short');
    await _save(tester);
    expect(api.writes, isEmpty);
    expect(find.text('Mínimo 8 caracteres'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), 'NewPassword123!');
    await tester.enterText(find.byType(TextFormField).at(2), 'NewPassword123!');
    await _save(tester);
    expect(api.writes.single, {'path': '/auth/change-password', 'data': {'currentPassword': 'OldPassword123!', 'newPassword': 'NewPassword123!'}, 'authenticated': true});
    expect(find.text('Contraseña actualizada correctamente.'), findsOneWidget);
  });
  testWidgets('actual router keeps recovery public even during pending 2FA', (tester) async {
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_Auth()),
      backendApiClientProvider.overrideWithValue(_Api()),
    ],);
    addTearDown(container.dispose);
    final router = container.read(goRouterProvider);
    router.go('${Routes.resetPassword}?token_hash=fixture');
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router,),),);
    await tester.pumpAndSettle();
    expect(find.text('Restablecer contraseña'), findsOneWidget);
    await container.read(authControllerProvider.notifier).signIn('fixture', 'password');
    await tester.pumpAndSettle();
    expect(container.read(authControllerProvider).pendingTwoFactor, isNotNull);
    expect(find.text('Restablecer contraseña'), findsOneWidget);
  });
  testWidgets('Android HTTPS link opens recovery on cold start and while app is open', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        'https://nivramop.com/reset-password?token_hash=cold-token';
    addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    final api = _Api();
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_Auth()),
      backendApiClientProvider.overrideWithValue(api),
    ],);
    addTearDown(container.dispose);
    final router = container.read(goRouterProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
    ),);
    await tester.pumpAndSettle();
    expect(find.text('Restablecer contraseña'), findsOneWidget);
    expect(tester.widget<ChangePasswordScreen>(find.byType(ChangePasswordScreen)).recoveryToken, 'cold-token');
    await router.routeInformationProvider.didPushRouteInformation(RouteInformation(
      uri: Uri.parse('https://nivramop.com/reset-password?token_hash=warm-token'),
    ),);
    await tester.pumpAndSettle();
    expect(tester.widget<ChangePasswordScreen>(find.byType(ChangePasswordScreen)).recoveryToken, 'warm-token');
    await tester.enterText(find.byType(TextFormField).at(0), 'NewPassword123!');
    await tester.enterText(find.byType(TextFormField).at(1), 'NewPassword123!');
    await _save(tester);
    expect((api.writes.single['data'] as Map)['tokenHash'], 'warm-token');
    expect(api.writes.single['authenticated'], false);
  });
}
