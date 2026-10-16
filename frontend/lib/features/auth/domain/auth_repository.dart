import '../../../shared/models/app_user.dart';
import '../../../shared/models/institution.dart';

class AuthSession {
  const AuthSession({required this.user, required this.institution});

  final AppUser user;
  final Institution institution;
}

class TwoFactorChallenge {
  const TwoFactorChallenge({
    required this.id,
    required this.method,
    this.expiresAt,
    this.resendAt,
    this.emailHint,
    this.debugCode,
    this.requiredByRole = false,
  });

  final String id;
  final String method;
  final DateTime? expiresAt;
  final DateTime? resendAt;
  final String? emailHint;
  final String? debugCode;
  final bool requiredByRole;
}

class SignInResult {
  const SignInResult.session(this.session) : challenge = null;
  const SignInResult.twoFactor(this.challenge) : session = null;

  final AuthSession? session;
  final TwoFactorChallenge? challenge;

  bool get requiresTwoFactor => challenge != null;
}

class TwoFactorStatus {
  const TwoFactorStatus({
    required this.enabled,
    required this.required,
    required this.method,
    required this.hasAuthenticator,
    required this.recoveryCodesRemaining,
    this.emailHint,
    this.verifiedAt,
  });

  final bool enabled;
  final bool required;
  final String method;
  final bool hasAuthenticator;
  final int recoveryCodesRemaining;
  final String? emailHint;
  final DateTime? verifiedAt;
}

class TwoFactorSetup {
  const TwoFactorSetup({
    this.id,
    this.method = 'totp',
    this.emailHint,
    this.expiresAt,
    this.resendAt,
    this.secret = '',
    this.otpauthUrl = '',
    required this.accountName,
    required this.issuer,
  });

  final String? id;
  final String method;
  final String? emailHint;
  final DateTime? expiresAt;
  final DateTime? resendAt;
  final String secret;
  final String otpauthUrl;
  final String accountName;
  final String issuer;
}

class TwoFactorEnableResult {
  const TwoFactorEnableResult({
    required this.enabled,
    required this.method,
    required this.recoveryCodes,
  });

  final bool enabled;
  final String method;
  final List<String> recoveryCodes;
}

abstract class AuthRepository {
  Future<Institution> resolveInstitution(String code);

  Future<SignInResult> signIn({
    Institution? institution,
    required String emailOrUsername,
    required String password,
  });

  Future<AuthSession> verifyTwoFactorLogin({
    required String challengeId,
    String? code,
    String? recoveryCode,
  });

  Future<void> signOut();

  Future<AuthSession?> currentSession();

  Future<void> sendPasswordReset(String email, {Institution? institution});

  Future<TwoFactorStatus> twoFactorStatus();

  Future<TwoFactorSetup> setupTwoFactor({String method = 'totp'});

  Future<TwoFactorSetup> sendTwoFactorEmailCode();

  Future<TwoFactorChallenge> resendTwoFactorLogin(String challengeId);

  Future<TwoFactorEnableResult> enableTwoFactor(String code,
      {String? challengeId,});

  Future<void> disableTwoFactor(
      {String? code, String? recoveryCode, String? challengeId,});
}
