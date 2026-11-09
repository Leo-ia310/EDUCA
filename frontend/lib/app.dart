import 'features/portal_access/access_widgets.dart';
import 'core/routing/route_paths.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/auth/presentation/widgets/brand_splash_overlay.dart';
import 'shared/models/app_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
      builder: (context, child) => _ResolvedPath(
        router: router,
        // `path` es la ruta REAL ya resuelta: así la compuerta del portal no se
        // queda mirando la ruta pedida (p. ej. `/assignments`) cuando la sesión
        // terminó y el router ya mandó al login (cargando para siempre encima).
        builder: (context, path) => BrandSplashOverlay(
          path: path,
          splashPath: Routes.splash,
          loginPath: Routes.login,
          child: PortalRouteGate(
            path: path,
            child: child ?? const SizedBox.shrink(),
            onHome: () => router.go(
              ref.read(authControllerProvider).user?.activeRole ==
                      AppRole.parent
                  ? Routes.parentDashboard
                  : Routes.studentDashboard,
            ),
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

/// Entrega la ruta REAL ya resuelta por el router. Tras una redirección
/// (p. ej. `/assignments` → login) `routeInformationProvider` conserva la ruta
/// pedida, así que se lee de la configuración del router. Este notifica en plena construcción
/// (al redirigir), por eso la actualización se difiere al siguiente fotograma
/// cuando hace falta: llamar a `setState` ahí rompería el árbol.
class _ResolvedPath extends StatefulWidget {
  const _ResolvedPath({required this.router, required this.builder});

  final GoRouter router;
  final Widget Function(BuildContext context, String path) builder;

  @override
  State<_ResolvedPath> createState() => _ResolvedPathState();
}

class _ResolvedPathState extends State<_ResolvedPath> {
  late String _path = _read();

  String _read() => widget.router.routerDelegate.currentConfiguration.uri.path;

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_onChange);
  }

  void _onChange() {
    if (!mounted || _read() == _path) return;
    // Nunca `setState` directo: el router también notifica durante la primera
    // construcción (con el planificador en reposo), y eso rompería el árbol.
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && _read() != _path) setState(() => _path = _read());
      })
      ..ensureVisualUpdate();
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _path);
}
