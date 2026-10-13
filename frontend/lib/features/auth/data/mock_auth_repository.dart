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
  Future<AuthSession> signIn({
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
    return AuthSession(
      user: _current!,
      institution: institution ?? _demoInstitution,
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
  Future<void> sendPasswordReset(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}
