import '../../../shared/models/app_user.dart';
import '../../../shared/models/institution.dart';

abstract class AuthRepository {
  Future<Institution> resolveInstitution(String code);

  Future<AppUser> signIn({
    required Institution institution,
    required String emailOrUsername,
    required String password,
  });

  Future<void> signOut();

  Future<AppUser?> currentUser();

  Future<void> sendPasswordReset(String email);
}
