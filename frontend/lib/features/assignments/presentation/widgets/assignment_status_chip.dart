import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities.dart';

/// Píldora de estado. Sobre una tarjeta blanca usa un tinte del color; sobre una
/// superficie pastel ([onPastel]) usa fondo blanco sólido para que la píldora
/// resalte sin lavarse contra el tinte de la tarjeta.
Widget _statusPill(BuildContext context, Color color, String label,
    {required bool onPastel}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: onPastel
          ? Colors.white.withValues(alpha: 0.85)
          : color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: context.textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class AssignmentStatusChip extends StatelessWidget {
  const AssignmentStatusChip({
    super.key,
    required this.status,
    this.onPastel = false,
  });
  final AssignmentStatus status;
  final bool onPastel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (color, label) = switch (status) {
      AssignmentStatus.draft => (palette.textMuted, 'Borrador'),
      AssignmentStatus.open => (palette.info, 'Abierta'),
      AssignmentStatus.dueSoon => (palette.warning, 'Vence pronto'),
      AssignmentStatus.overdue => (palette.danger, 'Vencida'),
      AssignmentStatus.closed => (palette.success, 'Cerrada'),
    };
    return _statusPill(context, color, label, onPastel: onPastel);
  }
}

class SubmissionStatusChip extends StatelessWidget {
  const SubmissionStatusChip({
    super.key,
    required this.status,
    this.onPastel = false,
  });
  final SubmissionStatus status;
  final bool onPastel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (color, label) = switch (status) {
      SubmissionStatus.pending => (palette.warning, 'Pendiente'),
      SubmissionStatus.submitted => (palette.info, 'Entregada'),
      SubmissionStatus.late => (palette.danger, 'Tarde'),
      SubmissionStatus.graded => (palette.success, 'Calificada'),
      SubmissionStatus.returned => (palette.info, 'Devuelta'),
    };
    return _statusPill(context, color, label, onPastel: onPastel);
  }
}
