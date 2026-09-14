import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../domain/entities.dart';
import '../../providers.dart';
import '../controllers/grades_controller.dart';
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

    return StudentDetailScaffold(
      title: 'Mis notas',
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: performance.when(
          loading: () => const SkeletonList(),
          error: (e, _) => ErrorStateView(message: '$e'),
          data: (perfs) {
            if (perfs.isEmpty) {
              return const EmptyState(
                icon: Icons.school_rounded,
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
                  color: palette.accentDeep,
                  onRefresh: () async =>
                      ref.invalidate(studentPerformanceProvider(studentId)),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
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
    final valid = performances.where((p) => p.evaluationCount > 0).toList();
    final avg = valid.isEmpty
        ? 0.0
        : valid.fold<double>(0, (a, p) => a + p.finalScore) / valid.length;
    final scored = double.parse(avg.toStringAsFixed(scale.decimals));
    final passing = performances.where((p) => p.passed).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2FA869),
            Color(0xFF35C97E),
            Color(0xFF2FB39A),
          ],
        ),
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.star_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Promedio general',
                  style: context.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      scored.toStringAsFixed(scale.decimals),
                      style: context.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '/ ${scale.maxValue.toStringAsFixed(0)}',
                      style: context.textTheme.titleMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    '$passing de ${performances.length} materias aprobadas',
                    style: context.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
