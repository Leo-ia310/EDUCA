import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/entities.dart';
import '../../providers.dart';
import '../controllers/grades_controller.dart';
import '../widgets/grade_pill.dart';

/// Drill-down: evaluaciones y notas de un estudiante en UNA materia.
class SubjectGradesScreen extends ConsumerWidget {
  const SubjectGradesScreen({
    super.key,
    required this.studentId,
    required this.classId,
  });

  final int studentId;
  final int classId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final periods = ref.watch(periodsProvider);
    final scaleAsync = ref.watch(defaultScaleProvider);
    final evalsAsync = ref.watch(studentEvaluationsProvider(
      (studentId: studentId, classId: classId),
    ));

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Detalle por materia'),
      ),
      child: SafeArea(
        bottom: false,
        child: scaleAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (scale) => periods.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (ps) => evalsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (data) {
                if (data.evaluations.isEmpty) {
                  return const EmptyState(
                    icon: Icons.assessment_outlined,
                    title: 'Sin evaluaciones',
                    subtitle: 'Todavía no hay actividades registradas.',
                  );
                }
                final groups = _groupByPeriod(data.evaluations, ps);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        child: SectionHeader(title: entry.key.name),
                      ),
                      EduCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            for (final e in entry.value) ...[
                              _EvaluationTile(
                                evaluation: e,
                                rawScore: data.grades[e.id],
                                scale: scale,
                              ),
                              if (e != entry.value.last)
                                Divider(
                                    height: 1,
                                    color: Theme.of(context)
                                        .dividerColor
                                        .withValues(alpha: 0.5)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Map<AcademicPeriod, List<Evaluation>> _groupByPeriod(
    List<Evaluation> evals,
    List<AcademicPeriod> periods,
  ) {
    final map = <AcademicPeriod, List<Evaluation>>{};
    for (final p in periods) {
      final list = evals.where((e) => e.periodId == p.id).toList();
      if (list.isNotEmpty) map[p] = list;
    }
    return map;
  }
}

class _EvaluationTile extends StatelessWidget {
  const _EvaluationTile({
    required this.evaluation,
    required this.rawScore,
    required this.scale,
  });

  final Evaluation evaluation;
  final double? rawScore;
  final GradingScale scale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fmt = DateFormat('d MMM', 'es');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: palette.limeSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              evaluation.kind == 'exam'
                  ? Icons.fact_check_outlined
                  : Icons.assignment_outlined,
              size: 18,
              color: palette.limeDeep,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  evaluation.title,
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${fmt.format(evaluation.date)} · ${evaluation.maxScore.toStringAsFixed(0)} pts',
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (rawScore == null)
            Text('Pendiente',
                style: context.textTheme.labelSmall
                    ?.copyWith(color: palette.textMuted))
          else
            GradePill(
              score: scale.normalize(rawScore!, rawMax: evaluation.maxScore),
              scale: scale,
              dense: true,
              showLabel: false,
            ),
        ],
      ),
    );
  }
}
