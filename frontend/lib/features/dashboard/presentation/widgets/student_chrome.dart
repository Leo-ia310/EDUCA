import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../notifications/providers.dart';
import '../../../profile/presentation/widgets/account_settings_menu.dart';

/// Radio de la curva con que el panel se monta sobre la barra azul (cóncava).
const double kStudentPanelRadius = 24;

/// Scaffold de las pantallas internas del alumno: barra superior azul
/// full-bleed (flecha atrás + título a la izquierda, notificaciones + config a
/// la derecha) y el contenido montado encima con esquinas superiores
/// redondeadas (curva cóncava), igual que el home.
class StudentDetailScaffold extends StatelessWidget {
  const StudentDetailScaffold({
    super.key,
    required this.title,
    required this.child,
    this.bottomNav = true,
    this.scrollable = true,
    this.onRefresh,
    this.fab,
    this.bodyPadding = const EdgeInsets.fromLTRB(16, 44, 16, 32),
    this.onBack,
    this.showBack = true,
  });

  final String title;
  final Widget child;
  final bool bottomNav;
  final bool scrollable;
  final Future<void> Function()? onRefresh;
  final Widget? fab;
  final EdgeInsets bodyPadding;

  /// Acción del botón atrás. Por defecto `context.pop()`.
  final VoidCallback? onBack;

  /// Muestra la flecha de volver. Desactívalo en destinos raíz del navbar.
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      padding: EdgeInsets.zero,
      topSafeArea: false,
      scrollable: scrollable,
      onRefresh: onRefresh,
      fab: fab,
      bottomNav: bottomNav ? const EducaBottomNav() : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudentTopBar(title: title, onBack: onBack, showBack: showBack),
          // Con scroll: el panel crece con el contenido. Sin scroll (listas
          // internas): el panel llena el alto restante y la lista scrollea
          // dentro.
          if (scrollable)
            StudentPanel(padding: bodyPadding, child: child)
          else
            Expanded(child: StudentPanel(padding: bodyPadding, child: child)),
        ],
      ),
    );
  }
}

/// Barra superior azul full-bleed con flecha atrás + título a la izquierda y
/// las acciones (notificaciones + configuración) a la derecha.
class StudentTopBar extends ConsumerWidget {
  const StudentTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.showBack = true,
  });

  final String title;
  final VoidCallback? onBack;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const barColor = EducaBottomNav.barColor;
    final topInset = MediaQuery.paddingOf(context).top;
    final badge = ref.watch(notificationsUnreadProvider).asData?.value ?? 0;
    return Container(
      // Borde inferior recto: el panel se monta encima y aporta la curva.
      padding: EdgeInsets.fromLTRB(showBack ? 4 : 16, topInset + 10, 12, 30),
      color: barColor,
      child: Row(
        children: [
          if (showBack) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              tooltip: 'Atrás',
              onPressed: onBack ?? () => context.pop(),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          EducaCircleAction(
            icon: Icons.notifications_rounded,
            tooltip: 'Notificaciones',
            badge: badge,
            onTap: () => context.go(Routes.alerts),
          ),
          const SizedBox(width: 10),
          const AccountSettingsMenu(circular: true),
        ],
      ),
    );
  }
}

/// Envuelve el contenido de una pantalla del alumno montándolo sobre la barra
/// azul con esquinas superiores redondeadas (curva cóncava).
class StudentPanel extends StatelessWidget {
  const StudentPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 44, 16, 32),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -kStudentPanelRadius),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(kStudentPanelRadius),
          ),
        ),
        padding: padding,
        child: child,
      ),
    );
  }
}

/// Botón de acción circular blanco translúcido (para el fondo azul), con badge.
class EducaCircleAction extends StatelessWidget {
  const EducaCircleAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.badge = 0,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badge;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white.withValues(alpha: 0.18),
          shape: const CircleBorder(),
          child: Tooltip(
            message: tooltip ?? '',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 46,
                height: 46,
                child: Icon(icon, size: 22, color: Colors.white),
              ),
            ),
          ),
        ),
        if (badge > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: context.palette.danger,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                '$badge',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
