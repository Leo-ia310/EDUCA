import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'educa_bottom_nav.dart';

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
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final EducaBottomNav? bottomNav;
  final Widget? fab;
  final EdgeInsetsGeometry padding;
  final bool scrollable;
  final Future<void> Function()? onRefresh;
  final Color? backgroundColor;

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
        color: context.palette.limeDeep,
        backgroundColor: context.palette.cardElevated,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      appBar: appBar,
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: bottomNav,
      floatingActionButton: fab,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
