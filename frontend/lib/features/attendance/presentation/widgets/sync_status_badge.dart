import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/attendance_sync_service.dart';

/// Indicador "X pendientes / sincronizado" que aparece en barras de
/// pantalla de asistencia.
///
/// Con [onDark] se dibuja para fondos azules/oscuros (cabeceras con degradado):
/// píldora blanca translúcida con texto claro. Sin eso, el verde translúcido de
/// «Al día» casi no se distingue sobre el azul.
class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key, this.compact = false, this.onDark = false});
  final bool compact;
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(attendanceSyncProvider);
    final palette = context.palette;

    Color bg;
    Color fg;
    IconData icon;
    String label;

    if (status.syncing) {
      bg = palette.info.withValues(alpha: 0.15);
      fg = palette.info;
      icon = Icons.sync;
      label = 'Sincronizando…';
    } else if (status.pending > 0) {
      bg = palette.warning.withValues(alpha: 0.15);
      fg = palette.warning;
      icon = Icons.cloud_off_rounded;
      label = compact
          ? '${status.pending} pend.'
          : '${status.pending} pendientes de sincronizar';
    } else if (status.lastError != null) {
      bg = palette.danger.withValues(alpha: 0.15);
      fg = palette.danger;
      icon = Icons.error_outline;
      label = 'Error al sincronizar';
    } else {
      bg = palette.success.withValues(alpha: 0.15);
      fg = palette.success;
      icon = Icons.cloud_done_rounded;
      label = compact ? 'Al día' : 'Sincronizado';
    }

    if (onDark) {
      bg = Colors.white.withValues(alpha: 0.22);
      fg = status.syncing
          ? Colors.white
          : status.pending > 0
              ? const Color(0xFFFFE08A)
              : status.lastError != null
                  ? const Color(0xFFFFC2C2)
                  : Colors.white;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: onDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.45))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.syncing)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: fg,
              ),
            )
          else
            Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
