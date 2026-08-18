import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/env.dart';

/// Singleton del cliente Supabase. Se inicializa en `main()` cuando hay
/// credenciales; en modo demo se omite la inicialización y los repositorios
/// usan datasources mock.
class SupabaseService {
  SupabaseService._();

  static Future<void> init() async {
    if (Env.isDemoMode) return;
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (Env.isDemoMode) return null;
  return SupabaseService.client;
});
