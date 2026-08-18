import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/errors/failures.dart';
import '../../../shared/models/app_role.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/institution.dart';
import '../domain/auth_repository.dart';

/// Implementación real contra Supabase. Asume el esquema definido en
/// `supabase/migrations`:
/// - `institutions(id, code, name, active)`
/// - `users(id, auth_user_id, institution_id, full_name, ...)`
/// - `user_roles(user_id, role_id)` con `roles(code)`
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);
  final sb.SupabaseClient _client;

  @override
  Future<Institution> resolveInstitution(String code) async {
    final res = await _client
        .from('institutions')
        .select('id, code, name, logo_url, primary_color, timezone, active')
        .eq('code', code.trim())
        .eq('active', true)
        .maybeSingle();

    if (res == null) {
      throw const AuthFailure('El código de colegio no es válido.');
    }
    return Institution.fromJson(res);
  }

  @override
  Future<AppUser> signIn({
    required Institution institution,
    required String emailOrUsername,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: emailOrUsername.trim(),
        password: password,
      );
      final session = response.session;
      if (session == null) {
        throw const AuthFailure('No se pudo iniciar sesión.');
      }

      final me = await _client
          .from('users')
          .select(
            'id, full_name, email, avatar_url, institution_id, '
            'user_roles(roles(code))',
          )
          .eq('auth_user_id', response.user!.id)
          .eq('institution_id', institution.id)
          .maybeSingle();

      if (me == null) {
        await _client.auth.signOut();
        throw const AuthFailure(
            'Tu usuario no pertenece a este colegio.');
      }

      final roleCodes = (me['user_roles'] as List? ?? const [])
          .map((e) => (e['roles']?['code']) as String?)
          .whereType<String>()
          .toList();

      final roles = roleCodes
          .map(AppRole.fromCode)
          .whereType<AppRole>()
          .toList();
      if (roles.isEmpty) {
        throw const AuthFailure('Usuario sin roles asignados.');
      }

      final fullName = me['full_name'] as String? ?? 'Usuario';
      return AppUser(
        id: me['id'].toString(),
        institutionId: institution.id,
        email: me['email'] as String? ?? emailOrUsername,
        fullName: fullName,
        firstName: fullName.split(' ').first,
        avatarUrl: me['avatar_url'] as String?,
        roles: roles,
        activeRole: roles.first,
      );
    } on sb.AuthException catch (e) {
      throw AuthFailure(e.message, cause: e);
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<AppUser?> currentUser() async => null; // implementar al rehidratar

  @override
  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }
}
