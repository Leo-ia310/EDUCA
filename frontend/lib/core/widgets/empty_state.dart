import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    this.title = 'Nada por aquí',
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.palette.limeSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: context.palette.limeDeep),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: context.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: context.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
