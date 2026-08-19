/// Variables de entorno inyectadas vía `--dart-define`.
class Env {
  Env._();

  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static const String backendApiBaseUrl =
      String.fromEnvironment(
        'BACKEND_API_BASE_URL',
        defaultValue: 'http://localhost:3000/api',
      );

  static String get businessApiUrl {
    final base = backendApiBaseUrl.trim();
    final normalized = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return normalized.endsWith('/business-api')
        ? normalized
        : '$normalized/business-api';
  }

  /// Clave pública VAPID para Web Push (no es secreta — viaja al cliente).
  /// La privada solo la usa `supabase/functions/send-push/`, nunca la app.
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
