import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../domain/entities.dart';
import 'grade_pill.dart';

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
    final palette = context.palette;
    return EduCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.limeSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.menu_book_rounded,
                    color: palette.limeDeep, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      performance.subjectName,
                      style: context.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(performance.teacherName,
                        style: context.textTheme.bodySmall),
                  ],
                ),
              ),
              GradePill(
                score: performance.finalScore,
                scale: scale,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PeriodBars(
            performance: performance,
            periods: periods,
            scale: scale,
          ),
        ],
      ),
    );
  }
}

class _PeriodBars extends StatelessWidget {
  const _PeriodBars({
    required this.performance,
    required this.periods,
    required this.scale,
  });

  final SubjectPerformance performance;
  final List<AcademicPeriod> periods;
  final GradingScale scale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        for (final p in periods)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    p.name,
                    style: context.textTheme.labelSmall,
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
                      backgroundColor: palette.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          _periodColor(performance.periodScores[p.id] ?? 0)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 60,
                  child: Text(
                    performance.periodScores[p.id] == null
                        ? '—'
                        : performance.periodScores[p.id]!
                            .toStringAsFixed(scale.decimals),
                    textAlign: TextAlign.end,
                    style: context.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
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
