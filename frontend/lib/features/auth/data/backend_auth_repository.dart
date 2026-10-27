import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:shared_preferences/shared_preferences.dart';

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
    required SharedPreferences prefs,
  })  : _api = api,
        _supabase = supabase,
        _prefs = prefs;

  final BackendApiClient _api;
  final sb.SupabaseClient _supabase;
  final SharedPreferences _prefs;

  static const _refreshTokenKey = 'auth.backend.refresh_token';
  static const _accessTokenKey = 'auth.backend.access_token';
  static const _institutionIdKey = 'auth.backend.institution_id';
  static const _institutionCodeKey = 'auth.backend.institution_code';
  static const _institutionNameKey = 'auth.backend.institution_name';
  static const _institutionCommercialKey =
      'auth.backend.institution_commercial_name';
  static const _institutionLogoKey = 'auth.backend.institution_logo_url';
  static const _institutionSavedAtKey = 'auth.backend.institution_saved_at';

  /// La copia local del colegio (nombre, logo) se renueva pasado este tiempo.
  static const _institutionTtl = Duration(hours: 12);

  @override
  Future<Institution> resolveInstitution(String code) async {
    final res = await _supabase
        .from('institutions')
        .select(
            'id, code, name, commercial_name, logo_url, primary_color, timezone, active',
        )
        .eq('code', code.trim())
        .eq('active', true)
        .maybeSingle();

    if (res == null) {
      throw const AuthFailure('El código de colegio no es válido.');
    }
    return Institution.fromJson(res);
  }

  @override
  Future<SignInResult> signIn({
    Institution? institution,
    required String emailOrUsername,
    required String password,
  }) async {
    try {
      final data = await _api.post(
        '/auth/login',
        data: {
          if (institution != null && institution.code.trim().isNotEmpty)
            'institutionCode': institution.code,
          'username': emailOrUsername.trim(),
          'password': password,
        },
        authenticated: false,
      );
      final map = (data as Map).cast<String, dynamic>();
      if (map['twoFactorRequired'] == true) {
        final challenge = (map['challenge'] as Map).cast<String, dynamic>();
        return SignInResult.twoFactor(
          TwoFactorChallenge(
            id: challenge['id'].toString(),
            method: challenge['method']?.toString() ?? 'email',
            expiresAt: DateTime.tryParse(
              challenge['expiresAt']?.toString() ?? '',
            ),
            emailHint: challenge['emailHint']?.toString(),
            resendAt:
                DateTime.tryParse(challenge['resendAt']?.toString() ?? ''),
            requiredByRole: challenge['requiredByRole'] == true,
          ),
        );
      }
      final session = await _authSessionFromLoginMap(map);
      return SignInResult.session(session);
    } on AuthFailure {
      rethrow;
    } catch (e) {
      throw _authFailureFrom(e, 'No se pudo iniciar sesión.');
    }
  }

  @override
  Future<AuthSession> verifyTwoFactorLogin({
    required String challengeId,
    String? code,
    String? recoveryCode,
  }) async {
    try {
      final data = await _api.post(
        '/auth/2fa/verify-login',
        data: {
          'challengeId': challengeId,
          if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
          if (recoveryCode != null && recoveryCode.trim().isNotEmpty)
            'recoveryCode': recoveryCode.trim(),
        },
        authenticated: false,
      );
      return await _authSessionFromLoginMap(
        (data as Map).cast<String, dynamic>(),
      );
    } catch (e) {
      throw _authFailureFrom(e, 'No se pudo verificar el código 2FA.');
    }
  }

  Future<AuthSession> _authSessionFromLoginMap(Map<String, dynamic> map) async {
    final session = (map['session'] as Map).cast<String, dynamic>();
    final refreshToken = session['refreshToken']?.toString();
    final accessToken = session['accessToken']?.toString();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const AuthFailure('El backend no devolvió una sesión válida.');
    }
    final authResponse = await _supabase.auth.setSession(
      refreshToken,
      accessToken: accessToken,
    );
    await _persistSession(authResponse.session);
    final resolvedInstitution = _institutionFromMap(
      (map['institution'] as Map).cast<String, dynamic>(),
    );
    await _persistInstitution(resolvedInstitution);
    return AuthSession(
      user: _userFromMap((map['user'] as Map).cast<String, dynamic>()),
      institution: resolvedInstitution,
    );
  }

  @override
  Future<void> signOut() async {
    try {
      if (_supabase.auth.currentSession != null) {
        await _api.post('/auth/logout');
      }
    } catch (_) {
      // Local logout must still work for an expired or unverified session.
    } finally {
      await _clearPersistedSession();
      await _supabase.auth.signOut();
    }
  }

  @override
  Future<AuthSession?> currentSession() async {
    final session = _supabase.auth.currentSession ?? await _restoreSession();
    final authUser = session?.user;
    if (authUser == null) return null;

    final me = await _supabase
        .from('users')
        .select(
          'id, full_name, email, avatar_url, institution_id, admin_permissions, '
          'user_roles(roles(code))',
        )
        .eq('auth_user_id', authUser.id)
        .maybeSingle();
    if (me == null) return null;

    final roleCodes = (me['user_roles'] as List? ?? const [])
        .map((e) => (e['roles']?['code']) as String?)
        .whereType<String>()
        .toList();
    final roles = AppRole.sortedByPriority(
      roleCodes.map(_roleFromCode).whereType<AppRole>(),
    );
    if (roles.isEmpty) return null;

    final institution = await _institutionForUser(me);
    if (institution == null) return null;

    final fullName = me['full_name'] as String? ?? 'Usuario';
    final user = AppUser(
      id: me['id'].toString(),
      institutionId: (me['institution_id'] as num).toInt(),
      email: me['email'] as String? ?? authUser.email ?? '',
      fullName: fullName,
      firstName: fullName.split(' ').first,
      avatarUrl: me['avatar_url'] as String?,
      roles: roles,
      activeRole: roles.first,
      adminPermissions: _permissionsFrom(me['admin_permissions']),
    );
    return AuthSession(user: user, institution: institution);
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
    final authResponse = await _supabase.auth.setSession(
      newRefreshToken,
      accessToken: session['accessToken']?.toString(),
    );
    await _persistSession(authResponse.session);
  }

  @override
  Future<void> sendPasswordReset(
    String email, {
    Institution? institution,
  }) async {
    await _api.post(
      '/auth/recover-password',
      data: {
        if (institution != null && institution.code.trim().isNotEmpty)
          'institutionCode': institution.code,
        'username': email.trim(),
      },
      authenticated: false,
    );
  }

  @override
  Future<TwoFactorStatus> twoFactorStatus() async {
    final data = await _api.get('/auth/2fa/status');
    final map = (data as Map).cast<String, dynamic>();
    return TwoFactorStatus(
      enabled: map['enabled'] == true,
      required: map['required'] == true,
      method: map['method']?.toString() ?? 'email',
      hasAuthenticator: map['hasAuthenticator'] == true,
      emailHint: map['emailHint']?.toString(),
      verifiedAt: DateTime.tryParse(map['verifiedAt']?.toString() ?? ''),
      recoveryCodesRemaining:
          int.tryParse('${map['recoveryCodesRemaining']}') ?? 0,
    );
  }

  @override
  Future<TwoFactorSetup> setupTwoFactor({String method = 'totp'}) async {
    final data = await _api.post(
      '/auth/2fa/setup',
      data: {'method': method},
    );
    final map = (data as Map).cast<String, dynamic>();
    return TwoFactorSetup(
      id: map['id']?.toString(),
      method: map['method']?.toString() ?? 'totp',
      emailHint: map['emailHint']?.toString(),
      expiresAt: DateTime.tryParse(map['expiresAt']?.toString() ?? ''),
      resendAt: DateTime.tryParse(map['resendAt']?.toString() ?? ''),
      secret: map['secret']?.toString() ?? '',
      otpauthUrl: map['otpauthUrl']?.toString() ?? '',
      accountName: map['accountName']?.toString() ?? '',
      issuer: map['issuer']?.toString() ?? 'Nivra',
    );
  }

  @override
  Future<TwoFactorEnableResult> enableTwoFactor(
    String code, {
    String? challengeId,
  }) async {
    final data = await _api.post(
      '/auth/2fa/enable',
      data: {
        'code': code.trim(),
        if (challengeId != null) 'challengeId': challengeId,
      },
    );
    final map = (data as Map).cast<String, dynamic>();
    return TwoFactorEnableResult(
      enabled: map['enabled'] == true,
      method: map['method']?.toString() ?? 'totp',
      recoveryCodes: ((map['recoveryCodes'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  @override
  Future<void> disableTwoFactor({
    String? code,
    String? recoveryCode,
    String? challengeId,
  }) async {
    await _api.post(
      '/auth/2fa/disable',
      data: {
        if (challengeId != null) 'challengeId': challengeId,
        if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
        if (recoveryCode != null && recoveryCode.trim().isNotEmpty)
          'recoveryCode': recoveryCode.trim(),
      },
    );
  }

  @override
  Future<TwoFactorSetup> sendTwoFactorEmailCode() async {
    final data = Map<String, dynamic>.from(
      await _api.post('/auth/2fa/email-code', data: {'purpose': 'disable'})
          as Map,
    );
    return TwoFactorSetup(
      id: data['id'].toString(),
      method: 'email',
      emailHint: data['emailHint']?.toString(),
      expiresAt: DateTime.tryParse('${data['expiresAt']}'),
      resendAt: DateTime.tryParse('${data['resendAt']}'),
      accountName: '',
      issuer: 'Nivra',
    );
  }

  @override
  Future<TwoFactorChallenge> resendTwoFactorLogin(String challengeId) async {
    final data = Map<String, dynamic>.from(
      await _api.post(
        '/auth/2fa/resend-login',
        data: {'challengeId': challengeId},
        authenticated: false,
      ) as Map,
    );
    final c = Map<String, dynamic>.from(data['challenge'] as Map);
    return TwoFactorChallenge(
      id: c['id'].toString(),
      method: 'email',
      emailHint: c['emailHint']?.toString(),
      expiresAt: DateTime.tryParse('${c['expiresAt']}'),
      resendAt: DateTime.tryParse('${c['resendAt']}'),
    );
  }

  Institution _institutionFromMap(Map<String, dynamic> map) {
    return Institution(
      id: int.tryParse('${map['id']}') ?? 0,
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
    );
  }

  Future<Institution?> _institutionForUser(Map<String, dynamic> user) async {
    final id = (user['institution_id'] as num?)?.toInt();
    final persistedId = _prefs.getInt(_institutionIdKey);
    final savedAt = _prefs.getInt(_institutionSavedAtKey);
    final fresh = savedAt != null &&
        DateTime.now().millisecondsSinceEpoch - savedAt <
            _institutionTtl.inMilliseconds;
    if (id != null && persistedId == id && fresh) {
      final code = _prefs.getString(_institutionCodeKey);
      final name = _prefs.getString(_institutionNameKey);
      if (code != null && name != null) {
        return Institution(
          id: id,
          code: code,
          name: name,
          commercialName: _prefs.getString(_institutionCommercialKey),
          logoUrl: _prefs.getString(_institutionLogoKey),
        );
      }
    }
    if (id == null) return null;
    final institution = await _supabase
        .from('institutions')
        .select(
            'id, code, name, commercial_name, logo_url, primary_color, timezone, active',
        )
        .eq('id', id)
        .maybeSingle();
    if (institution == null) return null;
    final resolved = Institution.fromJson(institution);
    await _persistInstitution(resolved);
    return resolved;
  }

  AppUser _userFromMap(Map<String, dynamic> map) {
    final fullName = map['fullName']?.toString() ?? 'Usuario';
    final roles = AppRole.sortedByPriority(
      ((map['roles'] as List?) ?? const [])
          .map((role) => _roleFromCode(role?.toString()))
          .whereType<AppRole>(),
    );
    if (roles.isEmpty) throw const AuthFailure('Usuario sin roles asignados.');
    return AppUser(
      id: map['id'].toString(),
      institutionId: int.tryParse('${map['institutionId']}') ?? 0,
      email: map['email']?.toString() ?? '',
      fullName: fullName,
      firstName: fullName.split(' ').first,
      roles: roles,
      activeRole: roles.first,
      adminPermissions: _permissionsFrom(map['adminPermissions']),
    );
  }

  /// `null` = sin restricciones; una lista (aunque vacía) = permisos exactos.
  List<String>? _permissionsFrom(Object? raw) =>
      raw is List ? [for (final p in raw) p.toString()] : null;

  AppRole? _roleFromCode(String? code) {
    if (code == 'super_admin') return AppRole.admin;
    return AppRole.fromCode(code);
  }

  Future<sb.Session?> _restoreSession() async {
    final refreshToken = _prefs.getString(_refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) return null;
    final accessToken = _prefs.getString(_accessTokenKey);
    try {
      final response = await _supabase.auth.setSession(
        refreshToken,
        accessToken:
            accessToken == null || accessToken.isEmpty ? null : accessToken,
      );
      await _persistSession(response.session);
      return response.session;
    } catch (_) {
      await _clearPersistedSession();
      return null;
    }
  }

  Future<void> _persistInstitution(Institution institution) async {
    await _prefs.setInt(_institutionIdKey, institution.id);
    await _prefs.setString(_institutionCodeKey, institution.code);
    await _prefs.setString(_institutionNameKey, institution.name);
    await _setOrRemove(_institutionCommercialKey, institution.commercialName);
    await _setOrRemove(_institutionLogoKey, institution.logoUrl);
    await _prefs.setInt(
      _institutionSavedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _setOrRemove(String key, String? value) =>
      value == null ? _prefs.remove(key) : _prefs.setString(key, value);

  Future<void> _persistSession(sb.Session? session) async {
    if (session == null) return;
    await _prefs.setString(_refreshTokenKey, session.refreshToken ?? '');
    await _prefs.setString(_accessTokenKey, session.accessToken);
  }

  Future<void> _clearPersistedSession() async {
    await _prefs.remove(_refreshTokenKey);
    await _prefs.remove(_accessTokenKey);
    await _prefs.remove(_institutionIdKey);
    await _prefs.remove(_institutionCodeKey);
    await _prefs.remove(_institutionNameKey);
    await _prefs.remove(_institutionCommercialKey);
    await _prefs.remove(_institutionLogoKey);
    await _prefs.remove(_institutionSavedAtKey);
  }

  AuthFailure _authFailureFrom(Object error, String fallback) {
    if (error is AuthFailure) return error;
    if (error is StateError && error.message.isNotEmpty) {
      return AuthFailure(error.message, cause: error);
    }
    return AuthFailure(fallback, cause: error);
  }
}
