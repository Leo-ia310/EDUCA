import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'brand_splash.dart';

/// Muestra la animación de marca como capa blanca por encima de TODA la app:
///
/// * al abrir la app (arranque), y
/// * al volver a la app tras salir de ella estando en el login.
///
/// Al ser una capa (no una pantalla que navega), los últimos
/// [BrandSplash.fadeOut] ms se desvanecen sobre la pantalla de destino, que ya
/// está debajo: el formulario del login aparece mientras la animación se va, no
/// de golpe, y lo escrito en el formulario se conserva.
class BrandSplashOverlay extends StatefulWidget {
  const BrandSplashOverlay({
    super.key,
    required this.path,
    required this.splashPath,
    required this.loginPath,
    required this.child,
  });

  /// Ruta actual de la app.
  final String path;

  /// Ruta de arranque (`/`): mientras siga ahí, la sesión aún no está resuelta.
  final String splashPath;

  /// Ruta del login.
  final String loginPath;
  final Widget child;

  @override
  State<BrandSplashOverlay> createState() => _BrandSplashOverlayState();
}

class _BrandSplashOverlayState extends State<BrandSplashOverlay> {
  late final AppLifecycleListener _lifecycle;
  bool _showing = true; // arranque en frío
  bool _coldStart = true;
  bool _nearEnd = false;
  bool _fading = false;
  bool _away = false;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onState);
  }

  void _onState(AppLifecycleState state) {
    // En el navegador recargar la página ya repite el arranque y cambiar de
    // pestaña no cuenta como salir de la app.
    if (kIsWeb) return;
    switch (state) {
      // `inactive` (barra de notificaciones, permisos) no cuenta como salir.
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _away = true;
      case AppLifecycleState.resumed:
        if (_away && widget.path == widget.loginPath && !_showing) {
          setState(() {
            _showing = true;
            _coldStart = false;
            _nearEnd = false;
            _fading = false;
            _run++;
          });
        }
        _away = false;
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _onNearEnd() {
    _nearEnd = true;
    _tryFade();
  }

  /// Empieza el desvanecimiento cuando la animación llega a su tramo final y la
  /// pantalla de destino ya está lista (en el arranque, cuando el router salió
  /// de `/`).
  void _tryFade() {
    if (!_showing || !_nearEnd || _fading) return;
    if (_coldStart &&
        (widget.path == widget.splashPath || widget.path.isEmpty)) {
      return;
    }
    setState(() => _fading = true);
    Future<void>.delayed(BrandSplash.fadeOut, () {
      if (!mounted) return;
      setState(() {
        _showing = false;
        _coldStart = false;
        _fading = false;
        _nearEnd = false;
      });
      restoreSystemBars();
    });
  }

  @override
  void didUpdateWidget(BrandSplashOverlay old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _tryFade();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (_showing)
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _fading ? 0 : 1,
              duration: BrandSplash.fadeOut,
              curve: Curves.easeInOut,
              // Absorbe los toques: no se puede usar lo de debajo mientras se anima.
              child: AbsorbPointer(
                absorbing: !_fading,
                child: Material(
                  color: Colors.white,
                  child: BrandSplash(
                    key: ValueKey(_run),
                    onNearEnd: _onNearEnd,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
