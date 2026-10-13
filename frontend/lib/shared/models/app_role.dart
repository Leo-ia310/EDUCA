/// Roles soportados por la plataforma. El `code` coincide con el almacenado
/// en la tabla `roles.code` y en `auth.users.raw_app_meta_data.roles[]`.
enum AppRole {
  student('student', 'Estudiante'),
  teacher('teacher', 'Maestro'),
  parent('parent', 'Padre/Tutor'),
  admin('admin', 'Administrador'),
  coordinator('coordinator', 'Coordinador'),
  director('director', 'Director');

  const AppRole(this.code, this.label);
  final String code;
  final String label;

  static AppRole? fromCode(String? code) {
    if (code == null) return null;
    for (final r in AppRole.values) {
      if (r.code == code) return r;
    }
    return null;
  }

  /// Prioridad para elegir el rol activo cuando un usuario tiene más de un rol.
  ///
  /// La base puede devolver `user_roles` sin orden estable. Si tomamos
  /// `roles.first`, un usuario admin que también tenga perfil de estudiante
  /// puede entrar por accidente al panel de estudiante. Por eso siempre
  /// ordenamos por privilegio antes de escoger el rol inicial.
  int get priority => switch (this) {
        AppRole.admin => 0,
        AppRole.director => 1,
        AppRole.coordinator => 2,
        AppRole.teacher => 3,
        AppRole.parent => 4,
        AppRole.student => 5,
      };

  static List<AppRole> sortedByPriority(Iterable<AppRole> roles) {
    final unique = <AppRole>{...roles}.toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    return unique;
  }

  /// Roles que usan el panel administrativo (permisos por persona).
  bool get isAdminPanel =>
      this == AppRole.admin ||
      this == AppRole.coordinator ||
      this == AppRole.director;

  /// Ruta del dashboard principal de este rol.
  String get dashboardRoute => switch (this) {
        AppRole.student => '/student/dashboard',
        AppRole.teacher => '/teacher/dashboard',
        AppRole.parent => '/parent/dashboard',
        AppRole.admin ||
        AppRole.coordinator ||
        AppRole.director =>
          '/admin/dashboard',
      };
}
