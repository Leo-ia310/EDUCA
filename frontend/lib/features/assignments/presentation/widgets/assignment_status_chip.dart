import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities.dart';

class AssignmentStatusChip extends StatelessWidget {
  const AssignmentStatusChip({super.key, required this.status});
  final AssignmentStatus status;

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
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
}

class SubmissionStatusChip extends StatelessWidget {
  const SubmissionStatusChip({super.key, required this.status});
  final SubmissionStatus status;

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
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
}
