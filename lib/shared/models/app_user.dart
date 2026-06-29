import 'package:equatable/equatable.dart';

import 'app_role.dart';

/// Usuario autenticado de la app. Combina datos de `auth.users` + `users` +
/// `persons`.
class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.institutionId,
    required this.email,
    required this.fullName,
    required this.roles,
    required this.activeRole,
    this.avatarUrl,
    this.firstName,
  });

  final String id;
  final int institutionId;
  final String email;
  final String fullName;
  final String? firstName;
  final String? avatarUrl;
  final List<AppRole> roles;
  final AppRole activeRole;

  AppUser copyWith({AppRole? activeRole}) => AppUser(
        id: id,
        institutionId: institutionId,
        email: email,
        fullName: fullName,
        firstName: firstName,
        avatarUrl: avatarUrl,
        roles: roles,
        activeRole: activeRole ?? this.activeRole,
      );

  String get displayFirstName => firstName ?? fullName.split(' ').first;

  @override
  List<Object?> get props =>
      [id, institutionId, email, fullName, roles, activeRole];
}
