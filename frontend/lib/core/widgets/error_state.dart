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
                color: context.palette.danger, size: 56,),
            const SizedBox(height: 12),
            Text(
              friendlyErrorMessage(message),
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

/// Quita los prefijos técnicos de Dart («Exception: », «Bad state: ») y evita
/// mostrar volcados de excepciones de red o de base de datos al usuario.
String friendlyErrorMessage(String raw) {
  var text = raw.trim();
  for (final prefix in const ['Exception: ', 'Bad state: ', 'Invalid argument(s): ']) {
    if (text.contains(prefix)) text = text.replaceFirst(prefix, '');
  }
  final technical = RegExp(
    r'(SocketException|ClientException|DioException|PostgrestException|AuthException|HandshakeException|TimeoutException|FormatException|XMLHttpRequest)',
  );
  if (technical.hasMatch(text)) {
    return 'No se pudo completar la operación. Revisa tu conexión e inténtalo otra vez.';
  }
  return text.isEmpty ? 'Ocurrió un error inesperado.' : text;
}
