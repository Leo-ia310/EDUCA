import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../routing/route_paths.dart';
import '../theme/app_theme.dart';
import 'brutal.dart';

/// Pantalla 404: ruta inexistente o no disponible. Siempre ofrece una salida
/// válida: volver atrás (si hay historial) o ir al inicio del rol actual.
class NotFoundScreen extends ConsumerStatefulWidget {
  const NotFoundScreen({super.key, this.location});

  /// Ruta que el usuario intentó abrir (se muestra como referencia).
  final String? location;

  @override
  ConsumerState<NotFoundScreen> createState() => _NotFoundScreenState();
}

class _NotFoundScreenState extends ConsumerState<NotFoundScreen>
    with TickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);
  late final AnimationController _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void dispose() {
    _float.dispose();
    _wiggle.dispose();
    super.dispose();
  }

  void _goHome() {
    final user = ref.read(authControllerProvider).user;
    context.go(user?.activeRole.dashboardRoute ?? Routes.login);
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      _goHome();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ink = palette.ink;
    final text = context.textTheme;
    final hasSession = ref.watch(authControllerProvider).user != null;
    final location = widget.location;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _wiggle.forward(from: 0),
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_float, _wiggle]),
                      builder: (_, child) {
                        final dy = (_float.value - 0.5) * 14;
                        // Meneo amortiguado al tocar el 404.
                        final t = _wiggle.value;
                        final angle =
                            math.sin(t * math.pi * 6) * 0.14 * (1 - t);
                        return Transform.translate(
                          offset: Offset(0, dy),
                          child: Transform.rotate(angle: angle, child: child),
                        );
                      },
                      child: BrutalBox(
                        color: palette.accent,
                        radius: Radii.lg,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 18,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('4', style: _big(context, palette.onAccent)),
                              Container(
                                width: 74,
                                height: 74,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                decoration: BoxDecoration(
                                  color: palette.sun,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: ink, width: 3),
                                ),
                                child: Icon(
                                  Icons.travel_explore_rounded,
                                  size: 40,
                                  color: ink,
                                ),
                              ),
                              Text('4', style: _big(context, palette.onAccent)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Página no encontrada',
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'La ruta que buscas no existe o fue movida.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                  if (location != null && location.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: palette.accentSoft,
                        borderRadius: BorderRadius.circular(Radii.sm),
                        border: Border.all(color: ink, width: 1.5),
                      ),
                      child: Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  BrutalButton(
                    expand: true,
                    onTap: _goHome,
                    icon: hasSession ? Icons.home_rounded : Icons.login_rounded,
                    label: hasSession
                        ? 'Ir a mi inicio'
                        : 'Ir al inicio de sesión',
                  ),
                  const SizedBox(height: 12),
                  BrutalButton(
                    expand: true,
                    onTap: _goBack,
                    icon: Icons.arrow_back_rounded,
                    label: 'Volver a la pantalla anterior',
                    color: palette.cardElevated,
                    foreground: ink,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _big(BuildContext context, Color color) =>
      (context.textTheme.displayLarge ?? const TextStyle()).copyWith(
        fontSize: 84,
        height: 1,
        fontWeight: FontWeight.w900,
        color: color,
      );
}
