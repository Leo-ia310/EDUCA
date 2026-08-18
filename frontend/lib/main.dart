import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/network/supabase_client.dart';
import 'core/services/hive_init.dart';
import 'core/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // App móvil → forzar orientación vertical.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await initializeDateFormatting('es');
  await HiveInit.init();
  await SupabaseService.init();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const Educa360App(),
    ),
  );
}
