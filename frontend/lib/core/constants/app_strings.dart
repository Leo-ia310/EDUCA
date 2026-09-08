/// Strings hardcoded en español (NI). Cuando se internacionalice, migrar a ARB.
class AppStrings {
  AppStrings._();

  static const appName = 'Educa360';

  // Login
  static const emailHint = 'Correo o usuario';
  static const passwordHint = 'Contraseña';
  static const loginCta = 'Ingresar';
  static const forgotPasswordCta = '¿Olvidaste tu contraseña?';

  // Errores
  static const errorGeneric = 'Ocurrió un error. Intenta de nuevo.';
  static const errorNoInternet = 'Sin conexión a internet.';
  static const errorInvalidCredentials = 'Credenciales inválidas.';
  static const errorInvalidInstitution = 'El código de colegio no es válido.';

  // Estados
  static const emptyTitle = 'Nada por aquí';
  static const emptySubtitle = 'No hay datos para mostrar.';
  static const retryCta = 'Reintentar';

  // Navegación
  static const navHome = 'Inicio';
  static const navSchedule = 'Horario';
  static const navMessages = 'Mensajes';
  static const navAlerts = 'Alertas';
  static const navProfile = 'Perfil';
}
