import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                color: context.palette.danger, size: 56),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
            ],
          ],
        ),
      ),
    );
  }
}
