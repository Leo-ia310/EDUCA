import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/env.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/backend_api_client.dart';
import '../../../core/network/supabase_client.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../shared/models/app_role.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/institution.dart';
import '../data/backend_auth_repository.dart';
import '../data/mock_auth_repository.dart';
import '../domain/auth_repository.dart';

/// Estado de sesiÃ³n global de la app.
class AuthState {
  const AuthState({
    this.user,
    this.institution,
    this.pendingTwoFactor,
    this.loading = false,
    this.error,
  });

  final AppUser? user;
  final Institution? institution;
  final TwoFactorChallenge? pendingTwoFactor;
  final bool loading;
  final String? error;

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    AppUser? user,
    Institution? institution,
    TwoFactorChallenge? pendingTwoFactor,
    bool? loading,
    String? error,
    bool clearError = false,
    bool clearUser = false,
    bool clearPendingTwoFactor = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      institution: institution ?? this.institution,
      pendingTwoFactor: clearPendingTwoFactor
          ? null
          : (pendingTwoFactor ?? this.pendingTwoFactor),
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (Env.isDemoMode) return MockAuthRepository();
  final client = ref.watch(supabaseClientProvider);
  final api = ref.watch(backendApiClientProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  if (client == null || api == null) return MockAuthRepository();
  return BackendAuthRepository(api: api, supabase: client, prefs: prefs);
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repo) : super(const AuthState(loading: true)) {
    _restoreSession();
  }
  final AuthRepository _repo;

  Future<void> _restoreSession() async {
    try {
      final session = await _repo.currentSession();
      state = state.copyWith(
        user: session?.user,
        institution: session?.institution,
        loading: false,
        clearError: true,
        clearPendingTwoFactor: true,
      );
    } catch (_) {
      state = state.copyWith(loading: false, clearUser: true);
    }
  }

  Future<bool> resolveInstitution(String code) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final institution = await _repo.resolveInstitution(code);
      state = state.copyWith(institution: institution, loading: false);
      return true;
    } on Failure catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: 'No se pudo validar el cÃ³digo.',
      );
      return false;
    }
  }

  Future<AppRole?> signIn(String emailOrUsername, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      // El login ya no pide código de colegio. El backend resuelve y valida
      // la institución según el usuario/email antes de autenticar.
      final session = await _repo.signIn(
        institution: state.institution,
        emailOrUsername: emailOrUsername,
        password: password,
      );
      if (session.requiresTwoFactor) {
        state = state.copyWith(
          pendingTwoFactor: session.challenge,
          loading: false,
        );
        return null;
      }
      final authSession = session.session!;
      state = state.copyWith(
        user: authSession.user,
        institution: authSession.institution,
        loading: false,
        clearPendingTwoFactor: true,
      );
      return authSession.user.activeRole;
    } on Failure catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return null;
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: 'No se pudo iniciar sesiÃ³n.',
      );
      return null;
    }
  }

  Future<AppRole?> verifyTwoFactor(
    String value, {
    bool recovery = false,
  }) async {
    final challenge = state.pendingTwoFactor;
    if (challenge == null) {
      state = state.copyWith(error: 'Inicia sesión nuevamente.');
      return null;
    }
    state = state.copyWith(loading: true, clearError: true);
    try {
      final session = await _repo.verifyTwoFactorLogin(
        challengeId: challenge.id,
        code: recovery ? null : value,
        recoveryCode: recovery ? value : null,
      );
      state = state.copyWith(
        user: session.user,
        institution: session.institution,
        loading: false,
        clearPendingTwoFactor: true,
      );
      return session.user.activeRole;
    } on Failure catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return null;
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: 'No se pudo verificar el código 2FA.',
      );
      return null;
    }
  }

  Future<bool> resendTwoFactor() async {
    final pending = state.pendingTwoFactor;
    if (pending == null || pending.method != 'email') return false;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final challenge = await _repo.resendTwoFactorLogin(pending.id);
      state = state.copyWith(
        pendingTwoFactor: challenge,
        loading: false,
        clearError: true,
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        loading: false,
        error: error is Failure
            ? error.message
            : error is StateError
                ? error.message.toString()
                : 'No se pudo reenviar el código.',
      );
      return false;
    }
  }

  Future<bool> sendPasswordReset(String email) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _repo.sendPasswordReset(email, institution: state.institution);
      state = state.copyWith(loading: false);
      return true;
    } on Failure catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: 'No se pudo enviar el correo de recuperación.',
      );
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _repo.signOut();
    } catch (_) {
      // A failed remote logout must not keep the UI authenticated.
    } finally {
      state = const AuthState();
    }
  }

  void setActiveRole(AppRole role) {
    final u = state.user;
    if (u == null) return;
    state = state.copyWith(user: u.copyWith(activeRole: role));
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});
