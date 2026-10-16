import 'package:educa360/core/errors/failures.dart';
import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/domain/auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:educa360/features/auth/presentation/screens/security_settings_screen.dart';
import 'package:educa360/features/auth/presentation/screens/two_factor_screen.dart';
import 'package:educa360/features/auth/presentation/widgets/authenticator_qr.dart';
import 'package:educa360/shared/models/app_role.dart';
import 'package:educa360/shared/models/app_user.dart';
import 'package:educa360/shared/models/institution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const secret = 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP';
const uri =
    'otpauth://totp/Nivra:fixture?secret=$secret&issuer=Nivra&algorithm=SHA1&digits=6&period=30';

class _Auth extends MockAuthRepository {
  bool enabled = false, sendFails = false, shortExpiry = false;
  String method = 'totp';
  int sends = 0, verifications = 0;
  @override
  Future<TwoFactorStatus> twoFactorStatus() async => TwoFactorStatus(
      enabled: enabled,
      required: false,
      method: method,
      hasAuthenticator: enabled && method == 'totp',
      recoveryCodesRemaining: enabled ? 10 : 0,);
  @override
  Future<TwoFactorSetup> setupTwoFactor({String method = 'totp'}) async {
    if (sendFails) throw StateError('No se pudo enviar el código por correo.');
    this.method = method;
    sends++;
    return TwoFactorSetup(
        id: 'setup-$sends',
        method: method,
        secret: method == 'totp' ? secret : '',
        otpauthUrl: method == 'totp' ? uri : '',
        accountName: 'fixture',
        issuer: 'Nivra',
        emailHint: 'fi***@example.com',
        expiresAt: DateTime.now().add(Duration(seconds: shortExpiry ? 2 : 300)),
        resendAt: DateTime.now().add(const Duration(seconds: 1)),);
  }

  @override
  Future<TwoFactorEnableResult> enableTwoFactor(String code,
      {String? challengeId,}) async {
    if (code != '123456') throw const AuthFailure('El código es incorrecto.');
    expect(challengeId, startsWith('setup-'));
    enabled = true;
    return TwoFactorEnableResult(
        enabled: true,
        method: method,
        recoveryCodes: List.generate(10, (i) => 'RECOVERY-$i'),);
  }

  @override
  Future<TwoFactorSetup> sendTwoFactorEmailCode() async {
    sends++;
    return const TwoFactorSetup(
        id: 'disable-1',
        method: 'email',
        emailHint: 'fi***@example.com',
        accountName: 'fixture',
        issuer: 'Nivra',);
  }

  @override
  Future<void> disableTwoFactor(
      {String? code, String? recoveryCode, String? challengeId,}) async {
    expect(challengeId, 'disable-1');
    if (code != '123456') throw const AuthFailure('El código es incorrecto.');
    enabled = false;
  }

  @override
  Future<SignInResult> signIn(
          {Institution? institution,
          required String emailOrUsername,
          required String password,}) async =>
      SignInResult.twoFactor(TwoFactorChallenge(
          id: 'login-1',
          method: method,
          emailHint: 'fi***@example.com',
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),),);
  @override
  Future<AuthSession> verifyTwoFactorLogin(
      {required String challengeId, String? code, String? recoveryCode,}) async {
    expect(challengeId, 'login-1');
    expect(code, '123456');
    verifications++;
    return const AuthSession(
        user: AppUser(
            id: '1',
            institutionId: 2,
            email: 'fixture@example.com',
            fullName: 'Fixture',
            roles: [AppRole.student],
            activeRole: AppRole.student,),
        institution: Institution(id: 2, code: 'TEST', name: 'Test'),);
  }
}

Widget app(MockAuthRepository repo) => ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
        theme: AppTheme.lightTheme, home: const SecuritySettingsScreen(),),);
Future<void> chooseEmail(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Correo electrónico').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Enviar código por correo'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'authenticator enrollment shows a local QR and manual secret, validates errors and active method',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _Auth();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activar con app autenticadora'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthenticatorQr), findsOneWidget);
    expect(
        tester.widget<AuthenticatorQr>(find.byType(AuthenticatorQr)).data, uri,);
    expect(find.text(secret), findsOneWidget);
    final field = find.widgetWithText(TextField, 'Código de 6 dígitos');
    await tester.ensureVisible(field);
    await tester.enterText(field, '000000');
    await tester.ensureVisible(find.text('Verificar y activar 2FA'));
    await tester.tap(find.text('Verificar y activar 2FA'));
    await tester.pumpAndSettle();
    expect(find.text('El código es incorrecto.'), findsOneWidget);
    await tester.enterText(field, '123456');
    await tester.tap(find.text('Verificar y activar 2FA'));
    await tester.pumpAndSettle();
    expect(find.text('Guarda tus códigos de recuperación'), findsOneWidget);
    await tester.tap(find.text('Ya los guardé'));
    await tester.pumpAndSettle();
    expect(find.text('Método activo: App autenticadora'), findsOneWidget);
    expect(find.byType(AuthenticatorQr), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'email enrollment shows sent/expired states and can request a fresh code',
      (tester) async {
    final repo = _Auth()..shortExpiry = true;
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    await chooseEmail(tester);
    expect(find.text('Código enviado'), findsOneWidget);
    expect(find.byType(AuthenticatorQr), findsNothing);
    expect(find.textContaining('fi***@example.com'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Código expirado. Solicita uno nuevo.'), findsOneWidget);
    final resend = find.text('Solicitar un nuevo código');
    await tester.ensureVisible(resend);
    await tester.tap(resend);
    await tester.pumpAndSettle();
    expect(repo.sends, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'email enrollment activates the selected method after confirmation',
      (tester) async {
    final repo = _Auth();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    await chooseEmail(tester);
    final field = find.widgetWithText(TextField, 'Código de 6 dígitos');
    await tester.ensureVisible(field);
    await tester.enterText(field, '123456');
    final button = find.text('Verificar y activar 2FA');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ya los guardé'));
    await tester.pumpAndSettle();
    expect(find.text('Método activo: Correo electrónico'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'email provider failure is an error, never a sent or enabled state',
      (tester) async {
    final repo = _Auth()..sendFails = true;
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    await chooseEmail(tester);
    expect(
        find.text('No se pudo enviar el código por correo.'), findsOneWidget,);
    expect(find.text('Código enviado'), findsNothing);
    expect(repo.enabled, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'disabling email 2FA requires a fresh code for the disable action',
      (tester) async {
    final repo = _Auth()
      ..enabled = true
      ..method = 'email';
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desactivar 2FA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Código de 6 dígitos'), '123456',);
    await tester.tap(find.text('Desactivar 2FA').last);
    await tester.pumpAndSettle();
    expect(find.text('2FA desactivado'), findsOneWidget);
    expect(repo.enabled, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final method in ['totp', 'email']) {
    testWidgets(
        'login uses the configured $method method and verifies before navigation',
        (tester) async {
      final repo = _Auth()..method = method;
      final router = GoRouter(initialLocation: '/verify', routes: [
        GoRoute(path: '/verify', builder: (_, __) => const TwoFactorScreen()),
        GoRoute(
            path: '/student/dashboard',
            builder: (_, __) => const Scaffold(body: Text('Sesión verificada')),),
      ],);
      await tester.pumpWidget(ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp.router(
              theme: AppTheme.lightTheme, routerConfig: router,),),);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
          tester.element(find.byType(TwoFactorScreen)),);
      await container
          .read(authControllerProvider.notifier)
          .signIn('fixture', 'password');
      await tester.pumpAndSettle();
      expect(
          find.text(method == 'email'
              ? 'Código enviado por correo'
              : 'Código de autenticador',),
          findsOneWidget,);
      await tester.enterText(
          find.widgetWithText(TextField, 'Código de 6 dígitos'), '123456',);
      await tester.tap(find.text('Verificar'));
      await tester.pumpAndSettle();
      expect(repo.verifications, 1);
      expect(find.text('Sesión verificada'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
  }
}
