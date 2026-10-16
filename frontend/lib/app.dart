import 'features/portal_access/access_widgets.dart';
import 'core/routing/route_paths.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'shared/models/app_role.dart';
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
      title: 'Nivra',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: router,
      builder: (context, child) => ValueListenableBuilder(
        valueListenable: router.routeInformationProvider,
        builder: (context, info, _) => PortalRouteGate(
          path: info.uri.path,
          child: child ?? const SizedBox.shrink(),
          onHome: () => router.go(
            ref.read(authControllerProvider).user?.activeRole == AppRole.parent
                ? Routes.parentDashboard
                : Routes.studentDashboard,
          ),
        ),
      ),
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
