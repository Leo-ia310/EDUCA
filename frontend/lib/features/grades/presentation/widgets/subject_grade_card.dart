import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../domain/entities.dart';

/// Tarjeta de notas por materia, estilo pastel del panel: fondo tintado por la
/// materia, ícono en círculo vívido, nombre + maestro, la nota final como
/// número grande en la tinta de la materia, y una mini-tendencia por periodos.
class SubjectGradeCard extends StatelessWidget {
  const SubjectGradeCard({
    super.key,
    required this.performance,
    required this.periods,
    required this.scale,
    this.onTap,
  });

  final SubjectPerformance performance;
  final List<AcademicPeriod> periods;
  final GradingScale scale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subjectColor(performance.subjectName));
    final isQual = scale.type == ScaleType.qualitative;
    final range = scale.ranges.firstWhere(
      (r) => r.contains(performance.finalScore),
      orElse: () => scale.ranges.last,
    );
    final headline = isQual
        ? range.label
        : performance.finalScore.toStringAsFixed(scale.decimals);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: s.vivid,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.menu_book_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            performance.subjectName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.titleMedium?.copyWith(
                              color: s.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            performance.teacherName,
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
                    // Nota como número grande.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          headline,
                          style: context.textTheme.headlineMedium?.copyWith(
                            color: s.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (!isQual) ...[
                          const SizedBox(width: 2),
                          Text(
                            '/${scale.maxValue.toStringAsFixed(0)}',
                            style: context.textTheme.labelSmall?.copyWith(
                              color: s.inkMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _PeriodBars(
                  performance: performance,
                  periods: periods,
                  scale: scale,
                  ink: s.ink,
                  inkMuted: s.inkMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PeriodBars extends StatelessWidget {
  const _PeriodBars({
    required this.performance,
    required this.periods,
    required this.scale,
    required this.ink,
    required this.inkMuted,
  });

  final SubjectPerformance performance;
  final List<AcademicPeriod> periods;
  final GradingScale scale;
  final Color ink;
  final Color inkMuted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final p in periods)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    p.name,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: inkMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (performance.periodScores[p.id] ?? 0) /
                          scale.maxValue,
                      minHeight: 8,
                      backgroundColor: ink.withValues(alpha: 0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _periodColor(performance.periodScores[p.id] ?? 0),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 44,
                  child: Text(
                    performance.periodScores[p.id] == null
                        ? '—'
                        : performance.periodScores[p.id]!
                            .toStringAsFixed(scale.decimals),
                    textAlign: TextAlign.end,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _periodColor(double score) {
    final range = scale.ranges.firstWhere(
      (r) => r.contains(score),
      orElse: () => scale.ranges.last,
    );
    return range.color ?? const Color(0xFF9BE000);
  }
}
