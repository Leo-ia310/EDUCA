import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/env.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/supabase_client.dart';
import '../../../shared/models/app_role.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/institution.dart';
import '../data/mock_auth_repository.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/auth_repository.dart';

/// Estado de sesión global de la app.
class AuthState {
  const AuthState({
    this.user,
    this.institution,
    this.loading = false,
    this.error,
  });

  final AppUser? user;
  final Institution? institution;
  final bool loading;
  final String? error;

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    AppUser? user,
    Institution? institution,
    bool? loading,
    String? error,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      institution: institution ?? this.institution,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (Env.isDemoMode) return MockAuthRepository();
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return MockAuthRepository();
  return SupabaseAuthRepository(client);
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repo) : super(const AuthState());
  final AuthRepository _repo;

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
          loading: false, error: 'No se pudo validar el código.');
      return false;
    }
  }

  Future<AppRole?> signIn(String emailOrUsername, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      // Ya no existe la pantalla de código de colegio: si aún no hay una
      // institución resuelta, se toma la institución por defecto (configurable
      // con `--dart-define=INSTITUTION_CODE`, `EDU360` en demo).
      final institution = state.institution ??
          await _repo.resolveInstitution(Env.defaultInstitutionCode);
      final user = await _repo.signIn(
        institution: institution,
        emailOrUsername: emailOrUsername,
        password: password,
      );
      state = state.copyWith(
          user: user, institution: institution, loading: false);
      return user.activeRole;
    } on Failure catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return null;
    } catch (_) {
      state = state.copyWith(
          loading: false, error: 'No se pudo iniciar sesión.');
      return null;
    }
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AuthState();
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
