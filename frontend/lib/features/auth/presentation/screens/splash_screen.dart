import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` cuando la animación de marca terminó completa. El router no saca al
/// usuario de `/` antes: así el splash dura lo mismo en el primer arranque que
/// en los siguientes, aunque la sesión ya esté lista de inmediato.
final splashFinishedProvider = StateProvider<bool>((ref) => false);

/// Pantalla de arranque. Muestra la animación de marca completa (una vuelta del
/// GIF) y avisa al router; el router decide a dónde ir: al dashboard del rol si
/// hay sesión activa, o al login si no.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _asset = 'assets/images/nivra_splash.gif';

  /// Duración de una vuelta del GIF (36 cuadros, 3,0 s).
  static const _animationTime = Duration(milliseconds: 3000);

  /// Tope de espera para decodificar el GIF antes de mostrarlo igual.
  static const _maxLoadWait = Duration(seconds: 2);

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: .96, end: 1).animate(curved);
    _slide = Tween<Offset>(
      begin: const Offset(0, .03),
      end: Offset.zero,
    ).animate(curved);

    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    // El GIF se decodifica ANTES de empezar a contar: en el primer arranque
    // (disco frío) cargarlo es lo lento, y así la animación no arranca a
    // medias ni se ve en cámara lenta.
    try {
      await precacheImage(const AssetImage(_asset), context)
          .timeout(_maxLoadWait);
    } catch (_) {
      // Si tarda o falla se muestra igual; el tiempo mínimo se mantiene.
    }
    if (!mounted) return;
    setState(() => _ready = true);
    _controller.forward();
    await Future<void>.delayed(_animationTime);
    if (!mounted) return;
    ref.read(splashFinishedProvider.notifier).state = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    // Devuelve las barras del sistema al estilo del tema activo (el splash las
    // pone blancas siempre).
    final dark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    );
    super.dispose();
  }

  /// Barras del sistema blancas con iconos oscuros: el splash es blanco aunque
  /// el teléfono esté en modo oscuro.
  static const _whiteSystemBars = SystemUiOverlayStyle(
    statusBarColor: Colors.white,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarDividerColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  @override
  Widget build(BuildContext context) {
    // Blanco siempre (aunque la app esté en modo oscuro): igual que el fondo del
    // GIF, sin «caja» visible y sin bandas oscuras en las barras del sistema.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _whiteSystemBars,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: _ready
                ? FadeTransition(
                    opacity: _fade,
                    child: SlideTransition(
                      position: _slide,
                      child: ScaleTransition(
                        scale: _scale,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Image.asset(
                              _asset,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
