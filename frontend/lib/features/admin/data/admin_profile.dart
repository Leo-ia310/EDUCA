import 'package:equatable/equatable.dart';

/// Perfil administrativo (admin, coordinador, director) con sus permisos
/// individuales. `customized == false` significa que conserva el acceso
/// histórico completo de su rol.
class AdminProfile extends Equatable {
  const AdminProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.roleCode,
    required this.permissions,
    this.phone,
    this.active = true,
    this.customized = false,
  });

  factory AdminProfile.fromJson(Map<String, dynamic> json) => AdminProfile(
        id: '${json['id']}',
        fullName: '${json['fullName'] ?? ''}',
        email: '${json['email'] ?? ''}',
        phone: json['phone'] as String?,
        active: json['active'] != false,
        roleCode: '${json['roleCode'] ?? 'admin'}',
        customized: json['customized'] == true,
        permissions: [
          for (final p in (json['permissions'] as List? ?? const [])) '$p',
        ],
      );

  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final bool active;
  final String roleCode;
  final bool customized;
  final List<String> permissions;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final a = parts.first[0];
    final b = parts.length > 1 ? parts.last[0] : '';
    return (a + b).toUpperCase();
  }

  @override
  List<Object?> get props =>
      [id, fullName, email, phone, active, roleCode, customized, permissions];
}
