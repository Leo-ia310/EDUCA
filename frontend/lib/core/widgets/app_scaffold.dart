import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'educa_bottom_nav.dart';

/// Ancho máximo del contenido. En pantallas anchas (web/tablet) el contenido se
/// centra en vez de estirarse de borde a borde como un teléfono agrandado.
const double kMaxContentWidth = 640;

/// Scaffold base con padding consistente, opcional bottom nav y FAB.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.child,
    this.appBar,
    this.bottomNav,
    this.fab,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 24),
    this.scrollable = true,
    this.onRefresh,
    this.backgroundColor,
    this.topSafeArea = true,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final EducaBottomNav? bottomNav;
  final Widget? fab;
  final EdgeInsetsGeometry padding;
  final bool scrollable;
  final Future<void> Function()? onRefresh;
  final Color? backgroundColor;

  /// Reserva el inset superior (status bar / notch). Se desactiva cuando el
  /// contenido dibuja su propia banda full-bleed hasta el borde superior (p. ej.
  /// la barra del home), que ya gestiona el inset por dentro.
  final bool topSafeArea;

  @override
  Widget build(BuildContext context) {
    Widget body = Padding(padding: padding, child: child);
    if (scrollable) {
      body = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        child: child,
      );
    }
    if (onRefresh != null) {
      body = RefreshIndicator(
        onRefresh: onRefresh!,
        color: context.palette.accentDeep,
        backgroundColor: context.palette.cardElevated,
        child: body,
      );
    }

    // En pantallas anchas, centrar el contenido con un ancho máximo (no estirar).
    body = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
        child: body,
      ),
    );

    return Scaffold(
      backgroundColor: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      // El navbar es opaco y reserva su propio espacio: el contenido termina por
      // encima de él (no queda tapado al llegar al final del scroll).
      extendBody: false,
      appBar: appBar,
      body: SafeArea(top: topSafeArea, bottom: false, child: body),
      bottomNavigationBar: bottomNav,
      floatingActionButton: fab,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
