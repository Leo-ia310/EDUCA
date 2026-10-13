import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../auth_controller.dart';

/// Pantalla de arranque. Muestra la animación de marca y luego decide a dónde
/// ir: si ya hay sesión activa va al dashboard del rol; si no, al login.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _minimumSplashTime = Duration(milliseconds: 2800);
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: .94, end: 1).animate(curved);
    _slide = Tween<Offset>(
      begin: const Offset(0, .05),
      end: Offset.zero,
    ).animate(curved);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(_minimumSplashTime);
      await _goNextWhenAuthIsReady();
    });
  }

  Future<void> _goNextWhenAuthIsReady() async {
    if (!mounted) return;
    final auth = ref.read(authControllerProvider);
    if (auth.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      return _goNextWhenAuthIsReady();
    }
    if (!mounted) return;
    if (auth.isAuthenticated) {
      context.go(auth.user!.activeRole.dashboardRoute);
    } else {
      context.go(Routes.login);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: ScaleTransition(
                scale: _scale,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Image.asset(
                      'assets/images/nivra_splash.gif',
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
