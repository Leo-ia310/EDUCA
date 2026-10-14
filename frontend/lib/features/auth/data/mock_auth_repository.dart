import '../../../core/errors/failures.dart';
import '../../../shared/models/app_role.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/institution.dart';
import '../domain/auth_repository.dart';

/// Implementación de demo: no toca Supabase. Permite navegar la app sin
/// backend configurado. Usuario y contraseña aceptados:
///
/// - `EDU360` como código de colegio.
/// - cualquier correo termiando en `@student.educa`, `@teacher.educa`,
///   `@parent.educa` o `@admin.educa` con contraseña `demo1234`.
class MockAuthRepository implements AuthRepository {
  AppUser? _current;

  static const _demoInstitution = Institution(
    id: 1,
    code: 'EDU360',
    name: 'Colegio Demo Educa360',
  );

  @override
  Future<Institution> resolveInstitution(String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (code.toUpperCase() != 'EDU360') {
      throw const AuthFailure('El código de colegio no es válido.');
    }
    return _demoInstitution;
  }

  @override
  Future<SignInResult> signIn({
    Institution? institution,
    required String emailOrUsername,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (password != 'demo1234') {
      throw const AuthFailure('Contraseña incorrecta.');
    }
    final email = emailOrUsername.toLowerCase().trim();
    final role = _roleFromEmail(email) ?? AppRole.student;
    _current = AppUser(
      id: 'demo-${role.code}',
      institutionId: (institution ?? _demoInstitution).id,
      email: email.contains('@') ? email : '$email@$role.educa',
      fullName: _displayNameFor(role),
      firstName: _firstNameFor(role),
      roles: [role],
      activeRole: role,
    );
    return SignInResult.session(
      AuthSession(
        user: _current!,
        institution: institution ?? _demoInstitution,
      ),
    );
  }

  @override
  Future<AuthSession> verifyTwoFactorLogin({
    required String challengeId,
    String? code,
    String? recoveryCode,
  }) async {
    final user = _current;
    if (user == null) throw const AuthFailure('Sesión demo no encontrada.');
    return const AuthSession(
      user: AppUser(
        id: 'demo-admin',
        institutionId: 1,
        email: 'admin@demo.com',
        fullName: 'Roberto Castillo',
        firstName: 'Roberto',
        roles: [AppRole.admin],
        activeRole: AppRole.admin,
      ),
      institution: _demoInstitution,
    );
  }

  AppRole? _roleFromEmail(String email) {
    // "developer" es un alias de acceso al panel técnico (superadmin). Usa rol
    // admin para pasar el RoleGuard del panel de desarrollador.
    if (email == 'demo2' ||
        email.startsWith('demo2@') ||
        email.endsWith('@developer.educa') ||
        email.startsWith('developer')) {
      return AppRole.admin;
    }
    if (email.endsWith('@teacher.educa') || email.startsWith('teacher')) {
      return AppRole.teacher;
    }
    if (email.endsWith('@parent.educa') || email.startsWith('parent')) {
      return AppRole.parent;
    }
    if (email.endsWith('@admin.educa') || email.startsWith('admin')) {
      return AppRole.admin;
    }
    if (email.endsWith('@student.educa') || email.startsWith('student')) {
      return AppRole.student;
    }
    return null;
  }

  String _displayNameFor(AppRole role) => switch (role) {
        AppRole.student => 'Julián Vargas',
        AppRole.teacher => 'Elena Ramírez',
        AppRole.parent => 'Marta Hernández',
        _ => 'Roberto Castillo',
      };

  String _firstNameFor(AppRole role) => switch (role) {
        AppRole.student => 'Julián',
        AppRole.teacher => 'Elena',
        AppRole.parent => 'Marta',
        _ => 'Roberto',
      };

  @override
  Future<void> signOut() async {
    _current = null;
  }

  @override
  Future<AuthSession?> currentSession() async {
    final user = _current;
    if (user == null) return null;
    return AuthSession(user: user, institution: _demoInstitution);
  }

  @override
  Future<void> sendPasswordReset(
    String email, {
    Institution? institution,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<TwoFactorStatus> twoFactorStatus() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
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
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return const TwoFactorSetup(
      secret: 'JBSWY3DPEHPK3PXP',
      otpauthUrl:
          'otpauth://totp/Nivra:demo?secret=JBSWY3DPEHPK3PXP&issuer=Nivra',
      accountName: 'demo',
      issuer: 'Nivra',
    );
  }

  @override
  Future<TwoFactorEnableResult> enableTwoFactor(String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return const TwoFactorEnableResult(
      enabled: true,
      method: 'totp',
      recoveryCodes: ['ABCDE-12345', 'FGHIJ-67890'],
    );
  }

  @override
  Future<void> disableTwoFactor({String? code, String? recoveryCode}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}
