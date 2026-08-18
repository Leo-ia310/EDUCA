import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.variant = QuickActionVariant.primary,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final QuickActionVariant variant;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bg = switch (variant) {
      QuickActionVariant.primary => palette.limeDeep,
      QuickActionVariant.dark => palette.cardContrast,
      QuickActionVariant.surface => palette.cardElevated,
    };
    final fg = switch (variant) {
      QuickActionVariant.primary => const Color(0xFF1E2218),
      QuickActionVariant.dark => Colors.white,
      QuickActionVariant.surface => Theme.of(context).colorScheme.onSurface,
    };

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: variant == QuickActionVariant.surface
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Theme.of(context).dividerColor),
                )
              : null,
          child: Row(
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: context.textTheme.titleMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward, color: fg, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

enum QuickActionVariant { primary, dark, surface }
