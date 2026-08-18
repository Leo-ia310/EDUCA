import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/entities.dart';
import '../../providers.dart';
import '../controllers/grades_controller.dart';
import '../widgets/grade_pill.dart';
import '../widgets/subject_grade_card.dart';

class StudentGradesScreen extends ConsumerWidget {
  const StudentGradesScreen({super.key, required this.studentId});
  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final periods = ref.watch(periodsProvider);
    final performance = ref.watch(studentPerformanceProvider(studentId));
    final scaleAsync = ref.watch(defaultScaleProvider);

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Mis notas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Descargar boletín',
            onPressed: () => context.push(
              '${Routes.reports}?studentId=$studentId',
            ),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: performance.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateView(message: '$e'),
          data: (perfs) {
            if (perfs.isEmpty) {
              return const EmptyState(
                icon: Icons.school_outlined,
                title: 'Sin notas todavía',
                subtitle: 'Cuando el maestro registre notas, aparecerán aquí.',
              );
            }
            return scaleAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorStateView(message: '$e'),
              data: (scale) => periods.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (ps) => RefreshIndicator(
                  color: palette.limeDeep,
                  onRefresh: () async =>
                      ref.invalidate(studentPerformanceProvider(studentId)),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _OverallCard(
                        performances: perfs,
                        scale: scale,
                      ),
                      const SizedBox(height: 16),
                      const SectionHeader(title: 'Materias'),
                      const SizedBox(height: 8),
                      for (final p in perfs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SubjectGradeCard(
                            performance: p,
                            periods: ps,
                            scale: scale,
                            onTap: () => context.push(
                              '${Routes.grades}/subject/${_classIdOf(p)}?studentId=$studentId',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Recupera el classId de forma pragmática desde el mock (no hay id en la
  /// entidad porque el consolidado es agnóstico a clase).
  int _classIdOf(SubjectPerformance p) => switch (p.subjectName) {
        'Matemáticas Avanzadas' => 101,
        'Historia Universal' => 201,
        'Física Cuántica' => 301,
        'Ética' => 401,
        'Biología Celular' => 501,
        _ => 0,
      };
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.performances, required this.scale});
  final List<SubjectPerformance> performances;
  final GradingScale scale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final valid = performances.where((p) => p.evaluationCount > 0).toList();
    final avg = valid.isEmpty
        ? 0.0
        : valid.fold<double>(0, (a, p) => a + p.finalScore) / valid.length;
    final scored = double.parse(avg.toStringAsFixed(scale.decimals));
    final passing = performances.where((p) => p.passed).length;
    return EduCard(
      color: palette.cardContrast,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Promedio general',
            style: context.textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                scored.toStringAsFixed(scale.decimals),
                style: context.textTheme.displaySmall?.copyWith(
                  color: palette.lime,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '/ ${scale.maxValue.toStringAsFixed(0)}',
                  style: context.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              GradePill(score: scored, scale: scale),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$passing de ${performances.length} materias aprobadas',
            style: context.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
