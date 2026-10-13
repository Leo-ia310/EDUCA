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
    this.adminPermissions,
  });

  final String id;
  final int institutionId;
  final String email;
  final String fullName;
  final String? firstName;
  final String? avatarUrl;
  final List<AppRole> roles;
  final AppRole activeRole;

  /// Permisos del panel admin concedidos a esta persona. `null` = sin
  /// restricciones (acceso histórico del rol, también en demo).
  final List<String>? adminPermissions;

  bool can(String code) =>
      adminPermissions == null || adminPermissions!.contains(code);

  AppUser copyWith({AppRole? activeRole}) => AppUser(
        id: id,
        institutionId: institutionId,
        email: email,
        fullName: fullName,
        firstName: firstName,
        avatarUrl: avatarUrl,
        roles: roles,
        activeRole: activeRole ?? this.activeRole,
        adminPermissions: adminPermissions,
      );

  String get displayFirstName => firstName ?? fullName.split(' ').first;

  @override
  List<Object?> get props =>
      [id, institutionId, email, fullName, roles, activeRole, adminPermissions];
}
