import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Barras del sistema blancas con iconos oscuros: la animación de marca es
/// blanca aunque el teléfono esté en modo oscuro.
const whiteSystemBars = SystemUiOverlayStyle(
  statusBarColor: Colors.white,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Colors.white,
  systemNavigationBarDividerColor: Colors.white,
  systemNavigationBarIconBrightness: Brightness.dark,
);

/// Devuelve las barras del sistema al estilo del tema activo.
void restoreSystemBars() {
  final dark = WidgetsBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.dark;
  SystemChrome.setSystemUIOverlayStyle(
    dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
  );
}

/// Animación de marca (GIF de Nivra) sobre fondo blanco: se decodifica ANTES de
/// empezar a contar y dura una vuelta completa (el GIF no se repite: se queda en
/// su último cuadro). Avisa con [onNearEnd] [fadeOut] antes de terminar, para que
/// quien la muestre la desvanezca justo en el último tramo y todo acabe a los
/// 3,0 s. Siempre arranca desde el primer cuadro, incluso si ya se mostró antes.
class BrandSplash extends StatefulWidget {
  const BrandSplash({super.key, required this.onNearEnd});

  final VoidCallback onNearEnd;

  static const asset = 'assets/images/nivra_splash.gif';

  /// Duración de una vuelta del GIF (3,0 s).
  static const animationTime = Duration(milliseconds: 3000);

  /// Últimos milisegundos en los que la animación se desvanece sobre lo que hay
  /// debajo (el formulario del login), para que no aparezca de golpe.
  static const fadeOut = Duration(milliseconds: 450);

  /// Tope de espera para decodificar el GIF antes de mostrarlo igual.
  static const _maxLoadWait = Duration(seconds: 2);

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash>
    with SingleTickerProviderStateMixin {
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
    // Se saca de la caché para que el GIF empiece en el cuadro 1 también en las
    // repeticiones (si no, retoma donde se quedó la vez anterior).
    PaintingBinding.instance.imageCache
        .evict(const AssetImage(BrandSplash.asset));
    // El GIF se decodifica ANTES de contar el tiempo: en el primer arranque
    // (disco frío) cargarlo es lo lento, y así no arranca a medias.
    try {
      await precacheImage(const AssetImage(BrandSplash.asset), context)
          .timeout(BrandSplash._maxLoadWait);
    } catch (_) {
      // Si tarda o falla se muestra igual; el tiempo mínimo se mantiene.
    }
    if (!mounted) return;
    setState(() => _ready = true);
    _controller.forward();
    await Future<void>.delayed(BrandSplash.animationTime - BrandSplash.fadeOut);
    if (!mounted) return;
    widget.onNearEnd();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: whiteSystemBars,
      child: ColoredBox(
        color: Colors.white,
        child: SafeArea(
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
                              BrandSplash.asset,
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
