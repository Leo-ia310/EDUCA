import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/domain/auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:educa360/features/auth/presentation/screens/login_screen.dart';
import 'package:educa360/shared/models/app_role.dart';
import 'package:educa360/shared/models/app_user.dart';
import 'package:educa360/shared/models/institution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  static const institution = Institution(
    id: 1,
    code: 'EDU360',
    name: 'Demo School',
  );

  @override
  Future<AuthSession?> currentSession() async => null;

  @override
  Future<Institution> resolveInstitution(String code) async => institution;

  @override
  Future<SignInResult> signIn({
    Institution? institution,
    required String emailOrUsername,
    required String password,
  }) async {
    final resolvedInstitution = institution ?? _FakeAuthRepository.institution;
    return SignInResult.session(
      AuthSession(
        institution: resolvedInstitution,
        user: AppUser(
          id: 'admin-1',
          institutionId: resolvedInstitution.id,
          email: emailOrUsername,
          fullName: 'Admin Demo',
          roles: const [AppRole.admin],
          activeRole: AppRole.admin,
        ),
      ),
    );
  }

  @override
  Future<AuthSession> verifyTwoFactorLogin({
    required String challengeId,
    String? code,
    String? recoveryCode,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> sendPasswordReset(
    String email, {
    Institution? institution,
  }) async {}

  @override
  Future<TwoFactorStatus> twoFactorStatus() async {
    return const TwoFactorStatus(
      enabled: false,
      required: false,
      method: 'email',
      hasAuthenticator: false,
      recoveryCodesRemaining: 0,
    );
  }

  @override
  Future<TwoFactorSetup> setupTwoFactor() async {
    return const TwoFactorSetup(
      secret: 'JBSWY3DPEHPK3PXP',
      otpauthUrl: 'otpauth://totp/Nivra:test?secret=JBSWY3DPEHPK3PXP',
      accountName: 'test',
      issuer: 'Nivra',
    );
  }

  @override
  Future<TwoFactorEnableResult> enableTwoFactor(String code) async {
    return const TwoFactorEnableResult(
      enabled: true,
      method: 'totp',
      recoveryCodes: [],
    );
  }

  @override
  Future<void> disableTwoFactor({String? code, String? recoveryCode}) async {}
}

void main() {
  test('mock auth trata demo2 como admin', () async {
    final repo = MockAuthRepository();
    final institution = await repo.resolveInstitution('EDU360');
    final session = await repo.signIn(
      institution: institution,
      emailOrUsername: 'demo2',
      password: 'demo1234',
    );

    expect(session.session!.user.activeRole, AppRole.admin);
    expect(session.session!.user.roles, [AppRole.admin]);
  });

  testWidgets('el login permite escribir en el campo de contraseña',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const LoginScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final passwordField = find.widgetWithText(TextFormField, 'Contraseña');
    expect(passwordField, findsOneWidget);

    await tester.enterText(passwordField, 'demo1234');
    await tester.pump();

    final fieldWidget = tester.widget<TextFormField>(passwordField);
    expect(fieldWidget.controller?.text, 'demo1234');

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: passwordField,
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.keyboardType, TextInputType.visiblePassword);
    expect(editable.autocorrect, isFalse);
    expect(editable.enableSuggestions, isFalse);
  });
}
