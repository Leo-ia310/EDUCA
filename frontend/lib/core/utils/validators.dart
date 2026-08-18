/// Validadores reutilizables para formularios.
class Validators {
  Validators._();

  static String? required(String? v, {String label = 'Este campo'}) {
    if (v == null || v.trim().isEmpty) return '$label es obligatorio';
    return null;
  }

  static String? institutionCode(String? v) {
    if (v == null || v.trim().isEmpty) return 'Ingresa el código del colegio';
    if (v.trim().length < 3) return 'El código es muy corto';
    return null;
  }

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Correo o usuario obligatorio';
    return null;
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Contraseña obligatoria';
    if (v.length < 6) return 'Mínimo 6 caracteres';
    return null;
  }
}
