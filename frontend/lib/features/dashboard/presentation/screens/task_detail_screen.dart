import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/floating_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/dashboard_models.dart';

/// Detalle de una tarea. Destino del container-transform desde la tarjeta de
/// tarea del dashboard del alumno.
class TaskDetailScreen extends StatelessWidget {
  const TaskDetailScreen({super.key, required this.task});
  final TaskBrief task;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (icon, color, label) = switch (task.status) {
      TaskStatus.pending => (Icons.edit_document, palette.danger, 'Pendiente'),
      TaskStatus.submitted => (
          Icons.upload_file_rounded,
          palette.info,
          'Entregada'
        ),
      TaskStatus.reviewed => (
          Icons.check_circle_rounded,
          palette.success,
          'Revisada'
        ),
      TaskStatus.late => (Icons.schedule_rounded, palette.warning, 'Atrasada'),
    };
    final subjectAccent = subjectInk(task.subject);

    return AppScaffold(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Tarea'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FloatingCard(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),
                      const Spacer(),
                      _Pill(label: label, color: color),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    task.title,
                    style: context.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  _Pill(label: task.subject, color: subjectAccent),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeader(title: 'Detalle'),
          const SizedBox(height: 8),
          EduCard(
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.menu_book_rounded,
                  label: 'Materia',
                  value: task.subject,
                ),
                Divider(
                    height: 20,
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.5),),
                _InfoRow(
                  icon: Icons.event_outlined,
                  label: 'Entrega',
                  value: task.dueDate ?? 'Sin fecha',
                ),
                Divider(
                    height: 20,
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.5),),
                _InfoRow(
                  icon: icon,
                  label: 'Estado',
                  value: label,
                  valueColor: color,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => context.push(Routes.assignments),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Abrir en Tareas'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Icon(icon, size: 18, color: palette.textMuted),
        const SizedBox(width: 10),
        Text(
          label,
          style:
              context.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
        ),
        const Spacer(),
        Text(
          value,
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: context.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
