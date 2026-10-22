import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

/// Data dependencies follow account, institution, role and permission changes;
/// transient loading/error emissions must not recreate repositories/streams.
final queryAuthProvider = Provider<AuthState>((ref) {
  final identity = ref.watch(
    authControllerProvider.select(
      (auth) => (auth.user, auth.institution),
    ),
  );
  return AuthState(user: identity.$1, institution: identity.$2);
});
