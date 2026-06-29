import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/dashboard_models.dart';

/// Tarjeta oscura "Mis Notas" del dashboard estudiante.
class GradesBlock extends StatelessWidget {
  const GradesBlock({
    super.key,
    required this.grades,
    required this.average,
    this.onDownload,
  });

  final List<GradeBrief> grades;
  final double average;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.cardContrast,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Mis Notas',
            style: context.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          for (final g in grades) ...[
            _GradeLine(grade: g),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 18),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Promedio Gral.',
                    style: context.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  average.toStringAsFixed(1),
                  style: context.textTheme.headlineSmall?.copyWith(
                    color: palette.lime,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Descargar Reporte'),
          ),
        ],
      ),
    );
  }
}

class _GradeLine extends StatelessWidget {
  const _GradeLine({required this.grade});
  final GradeBrief grade;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final statusColor = switch (grade.status) {
      GradeStatus.passed => palette.success,
      GradeStatus.pending => palette.warning,
      GradeStatus.lowPerformance => palette.danger,
    };
    final statusLabel = switch (grade.status) {
      GradeStatus.passed => 'Aprobado',
      GradeStatus.pending => 'En curso',
      GradeStatus.lowPerformance => 'Bajo rend.',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                grade.subject,
                style: context.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                grade.activity,
                style: context.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              grade.score.toStringAsFixed(1),
              style: context.textTheme.titleLarge?.copyWith(
                color: palette.lime,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              statusLabel,
              style: context.textTheme.labelSmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
