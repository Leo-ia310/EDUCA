import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../domain/dashboard_models.dart';

class TaskRow extends StatelessWidget {
  const TaskRow({super.key, required this.task});
  final TaskBrief task;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (icon, color) = switch (task.status) {
      TaskStatus.pending => (Icons.edit_document, palette.danger),
      TaskStatus.submitted => (Icons.upload_file_rounded, palette.info),
      TaskStatus.reviewed => (Icons.check_circle_rounded, palette.success),
      TaskStatus.late => (Icons.schedule_rounded, palette.warning),
    };
    final cta = switch (task.status) {
      TaskStatus.pending => 'Subir Trabajo',
      TaskStatus.submitted => 'En revisión',
      TaskStatus.reviewed => 'Revisado',
      TaskStatus.late => 'Tarde',
    };
    final ctaBg = switch (task.status) {
      TaskStatus.pending => palette.cardContrast,
      TaskStatus.reviewed => palette.limeSoft,
      _ => palette.surfaceAlt,
    };
    final ctaFg = switch (task.status) {
      TaskStatus.pending => Colors.white,
      TaskStatus.reviewed => palette.limeDeep,
      _ => Theme.of(context).colorScheme.onSurface,
    };
    return EduCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  task.subject,
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: ctaBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              cta,
              style: context.textTheme.labelMedium?.copyWith(
                color: ctaFg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
