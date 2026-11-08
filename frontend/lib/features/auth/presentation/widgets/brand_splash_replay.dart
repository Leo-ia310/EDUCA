import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'brand_splash.dart';

/// Vuelve a mostrar la animación de marca cuando el usuario SALE de la app y
/// VUELVE estando en el login. Va como capa encima del login (no navega), así
/// lo que ya escribió en el formulario se conserva.
///
/// Solo en la app móvil: en el navegador, recargar la página ya repite el
/// arranque y cambiar de pestaña no cuenta como salir de la app.
class BrandSplashReplay extends StatefulWidget {
  const BrandSplashReplay({
    super.key,
    required this.path,
    required this.loginPath,
    required this.child,
  });

  /// Ruta actual de la app.
  final String path;

  /// Ruta del login.
  final String loginPath;
  final Widget child;

  @override
  State<BrandSplashReplay> createState() => _BrandSplashReplayState();
}

class _BrandSplashReplayState extends State<BrandSplashReplay> {
  late final AppLifecycleListener _lifecycle;
  bool _away = false;
  bool _showing = false;
  bool _fadingOut = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onState);
  }

  void _onState(AppLifecycleState state) {
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
            _fadingOut = false;
          });
        }
        _away = false;
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _finish() {
    setState(() => _fadingOut = true);
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _showing = false);
      restoreSystemBars();
    });
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
              opacity: _fadingOut ? 0 : 1,
              duration: const Duration(milliseconds: 350),
              // Absorbe los toques: no se puede usar el login debajo mientras se anima.
              child: AbsorbPointer(
                child: Material(
                  color: Colors.white,
                  child: BrandSplash(onFinished: _finish),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
