import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/errors/failures.dart';
import '../../../core/network/backend_api_client.dart';
import '../../../shared/models/app_role.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/institution.dart';
import '../domain/auth_repository.dart';

class BackendAuthRepository implements AuthRepository {
  BackendAuthRepository({
    required BackendApiClient api,
    required sb.SupabaseClient supabase,
  })  : _api = api,
        _supabase = supabase;

  final BackendApiClient _api;
  final sb.SupabaseClient _supabase;

  @override
  Future<Institution> resolveInstitution(String code) async {
    final res = await _supabase
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
      final data = await _api.post(
        '/auth/login',
        data: {
          'institutionCode': institution.code,
          'username': emailOrUsername.trim(),
          'password': password,
        },
        authenticated: false,
      );
      final map = (data as Map).cast<String, dynamic>();
      final session = (map['session'] as Map).cast<String, dynamic>();
      final refreshToken = session['refreshToken']?.toString();
      final accessToken = session['accessToken']?.toString();
      if (refreshToken == null || refreshToken.isEmpty) {
        throw const AuthFailure('El backend no devolvió una sesión válida.');
      }
      await _supabase.auth.setSession(refreshToken, accessToken: accessToken);
      return _userFromMap((map['user'] as Map).cast<String, dynamic>());
    } on AuthFailure {
      rethrow;
    } catch (e) {
      throw AuthFailure('No se pudo iniciar sesión.', cause: e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      if (_supabase.auth.currentSession != null) {
        await _api.post('/auth/logout');
      }
    } finally {
      await _supabase.auth.signOut();
    }
  }

  @override
  Future<AppUser?> currentUser() async {
    final authUser = _supabase.auth.currentSession?.user;
    if (authUser == null) return null;

    final me = await _supabase
        .from('users')
        .select(
          'id, full_name, email, avatar_url, institution_id, '
          'user_roles(roles(code))',
        )
        .eq('auth_user_id', authUser.id)
        .maybeSingle();
    if (me == null) return null;

    final roleCodes = (me['user_roles'] as List? ?? const [])
        .map((e) => (e['roles']?['code']) as String?)
        .whereType<String>()
        .toList();
    final roles = roleCodes.map(_roleFromCode).whereType<AppRole>().toList();
    if (roles.isEmpty) return null;

    final fullName = me['full_name'] as String? ?? 'Usuario';
    return AppUser(
      id: me['id'].toString(),
      institutionId: (me['institution_id'] as num).toInt(),
      email: me['email'] as String? ?? authUser.email ?? '',
      fullName: fullName,
      firstName: fullName.split(' ').first,
      avatarUrl: me['avatar_url'] as String?,
      roles: roles,
      activeRole: roles.first,
    );
  }

  Future<void> refreshSession(String refreshToken) async {
    final data = await _api.post(
      '/auth/refresh',
      data: {
        'refreshToken': refreshToken,
      },
      authenticated: false,
    );
    final session = ((data as Map)['session'] as Map).cast<String, dynamic>();
    final newRefreshToken = session['refreshToken']?.toString() ?? refreshToken;
    await _supabase.auth.setSession(
      newRefreshToken,
      accessToken: session['accessToken']?.toString(),
    );
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await _api.post(
      '/auth/recover-password',
      data: {
        'institutionCode': 'EDU360',
        'username': email.trim(),
      },
      authenticated: false,
    );
  }

  AppUser _userFromMap(Map<String, dynamic> map) {
    final fullName = map['fullName']?.toString() ?? 'Usuario';
    final roles = ((map['roles'] as List?) ?? const [])
        .map((role) => _roleFromCode(role?.toString()))
        .whereType<AppRole>()
        .toList();
    if (roles.isEmpty) throw const AuthFailure('Usuario sin roles asignados.');
    return AppUser(
      id: map['id'].toString(),
      institutionId: int.tryParse('${map['institutionId']}') ?? 0,
      email: map['email']?.toString() ?? '',
      fullName: fullName,
      firstName: fullName.split(' ').first,
      roles: roles,
      activeRole: roles.first,
    );
  }

  AppRole? _roleFromCode(String? code) {
    if (code == 'super_admin') return AppRole.admin;
    return AppRole.fromCode(code);
  }
}
