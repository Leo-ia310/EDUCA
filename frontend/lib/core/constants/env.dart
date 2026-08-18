/// Variables de entorno inyectadas vía `--dart-define`.
class Env {
  Env._();

  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Clave pública VAPID para Web Push (no es secreta — viaja al cliente).
  /// La privada solo la usa `backend/functions/send-push/`, nunca la app.
  /// Generar el par con `npx web-push generate-vapid-keys`.
  static const String vapidPublicKey =
      String.fromEnvironment('VAPID_PUBLIC_KEY', defaultValue: '');

  /// Fuerza el modo demo aunque haya credenciales de Supabase. Útil para
  /// mostrar la app completa con datos mock sin depender del backend.
  /// Actívalo con `--dart-define=DEMO=true` (ver `run_demo.ps1`).
  static const bool forceDemo =
      bool.fromEnvironment('DEMO', defaultValue: false);

  /// `true` cuando faltan credenciales o se fuerza demo: la app correrá en
  /// **modo demo** usando repositorios mock para que el shell visual sea
  /// navegable y todas las funciones respondan.
  static bool get isDemoMode =>
      forceDemo || supabaseUrl.isEmpty || supabaseAnonKey.isEmpty;
}
