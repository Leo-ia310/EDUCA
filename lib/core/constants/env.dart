/// Variables de entorno inyectadas vía `--dart-define`.
class Env {
  Env._();

  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// `true` cuando faltan credenciales: la app correrá en **modo demo**
  /// usando repositorios mock para que el shell visual sea navegable.
  static bool get isDemoMode =>
      supabaseUrl.isEmpty || supabaseAnonKey.isEmpty;
}
