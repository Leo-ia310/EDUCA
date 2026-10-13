import '../../../shared/models/app_user.dart';
import '../../../shared/models/institution.dart';

class AuthSession {
  const AuthSession({required this.user, required this.institution});

  final AppUser user;
  final Institution institution;
}

abstract class AuthRepository {
  Future<Institution> resolveInstitution(String code);

  Future<AuthSession> signIn({
    Institution? institution,
    required String emailOrUsername,
    required String password,
  });

  Future<void> signOut();

  Future<AuthSession?> currentSession();

  Future<void> sendPasswordReset(String email);
}
