import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/notifications/domain/notifications_bootstrap.dart';

class Educa360App extends ConsumerStatefulWidget {
  const Educa360App({super.key});

  @override
  ConsumerState<Educa360App> createState() => _Educa360AppState();
}

class _Educa360AppState extends ConsumerState<Educa360App> {
  @override
  void initState() {
    super.initState();
    // Arranca el pipeline de notificaciones (permisos, feed, deep-links).
    // Se mantiene vivo mientras el widget raíz esté montado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsBootstrapProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeControllerProvider);
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'Educa360',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es'),
        Locale('en'),
      ],
      locale: const Locale('es'),
    );
  }
}
