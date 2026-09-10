import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../domain/dashboard_models.dart';

/// Bloque "Mis Notas" del perfil, estilo panel: cada materia como fila pastel
/// (tintada por su color) con la nota como número, y el promedio general en un
/// mini-hero verde.
class GradesBlock extends StatelessWidget {
  const GradesBlock({
    super.key,
    required this.grades,
    required this.average,
  });

  final List<GradeBrief> grades;
  final double average;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in grades) ...[
          _GradeRow(grade: g),
          const SizedBox(height: 8),
        ],
        _AverageHero(average: average),
      ],
    );
  }
}

class _GradeRow extends StatelessWidget {
  const _GradeRow({required this.grade});
  final GradeBrief grade;

  @override
  Widget build(BuildContext context) {
    final s = pastelSurface(subjectColor(grade.subject));
    final statusBase = switch (grade.status) {
      GradeStatus.passed => const Color(0xFF2E9E5B),
      GradeStatus.pending => const Color(0xFFCF8A1E),
      GradeStatus.lowPerformance => const Color(0xFFD3453B),
    };
    final statusLabel = switch (grade.status) {
      GradeStatus.passed => 'Aprobado',
      GradeStatus.pending => 'En curso',
      GradeStatus.lowPerformance => 'Bajo rend.',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
            child: const Icon(
              Icons.menu_book_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  grade.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall?.copyWith(
                    color: s.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  grade.activity,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: s.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                grade.score.toStringAsFixed(1),
                style: context.textTheme.titleLarge?.copyWith(
                  color: s.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                statusLabel,
                style: context.textTheme.labelSmall?.copyWith(
                  color: statusBase,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AverageHero extends StatelessWidget {
  const _AverageHero({required this.average});
  final double average;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2FA869), Color(0xFF35C97E), Color(0xFF2FB39A)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.star_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
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
            style: context.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
