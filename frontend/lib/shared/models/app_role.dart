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

  /// Ruta del dashboard principal de este rol.
  String get dashboardRoute => switch (this) {
        AppRole.student => '/student/dashboard',
        AppRole.teacher => '/teacher/dashboard',
        AppRole.parent => '/parent/dashboard',
        AppRole.admin || AppRole.coordinator || AppRole.director =>
          '/admin/dashboard',
      };
}
