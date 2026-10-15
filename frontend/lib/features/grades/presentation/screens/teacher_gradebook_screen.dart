import '../../../collaborations/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/animated_count.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../assignments/providers.dart';
import '../../../attendance/domain/entities.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../domain/entities.dart';
import '../../domain/grades_repository.dart';
import '../../providers.dart';
import '../controllers/gradebook_controller.dart';
import '../widgets/grade_pill.dart';

/// Vista tipo hoja de cálculo: filas = estudiantes, columnas = evaluaciones.
class TeacherGradebookScreen extends ConsumerStatefulWidget {
  const TeacherGradebookScreen({super.key});

  @override
  ConsumerState<TeacherGradebookScreen> createState() =>
      _TeacherGradebookScreenState();
}

class _TeacherGradebookScreenState
    extends ConsumerState<TeacherGradebookScreen> {
  int? _classId;
  String? _periodId;

  @override
  Widget build(BuildContext context) {
    final periodsAsync = ref.watch(periodsProvider);
    final classesAsync = ref.watch(teacherClassesProvider);
    // Periodos sin ids repetidos; el seleccionado debe existir en la lista
    // (si no, se usa el vigente o el primero) para no romper el dropdown.
    final periods = _uniquePeriods(periodsAsync.valueOrNull ?? const []);
    final classes = (classesAsync.valueOrNull ?? const <ClassSessionBrief>[])
        .where((c) => c.can('students.view'))
        .toList();
    final selectedClassId = classes.any((c) => c.classId == _classId)
        ? _classId
        : classes.isEmpty
            ? null
            : classes.first.classId;
    final selectedPeriodId = periods.any((p) => p.id == _periodId)
        ? _periodId
        : periods.isEmpty
            ? null
            : periods
                .firstWhere((p) => p.isCurrent, orElse: () => periods.first)
                .id;
    final args = selectedClassId == null || selectedPeriodId == null
        ? null
        : GradebookArgs(classId: selectedClassId, periodId: selectedPeriodId);
    final data = args == null ? null : ref.watch(gradebookProvider(args));
    final scaleAsync = ref.watch(gradebookScaleProvider);

    return StudentDetailScaffold(
      title: 'Libro de notas',
      scrollable: false,
      bottomNav: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Filters(
              classId: selectedClassId,
              periodId: selectedPeriodId,
              classes: classes,
              periods: periods,
              onClass: (v) => setState(() => _classId = v),
              onPeriod: (v) => setState(() => _periodId = v),
            ),
            Expanded(
              child: _GradebookBody(
                classesLoading: classesAsync.isLoading,
                periodsLoading: periodsAsync.isLoading,
                hasClasses: classes.isNotEmpty,
                hasPeriods: periods.isNotEmpty,
                data: data,
                scaleAsync: scaleAsync,
                args: args,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<AcademicPeriod> _uniquePeriods(List<AcademicPeriod> list) {
  final seen = <String>{};
  return [
    for (final p in list)
      if (seen.add(p.id)) p,
  ];
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.classId,
    required this.periodId,
    required this.classes,
    required this.periods,
    required this.onClass,
    required this.onPeriod,
  });

  final int? classId;
  final String? periodId;
  final List<ClassSessionBrief> classes;
  final List<AcademicPeriod> periods;
  final ValueChanged<int> onClass;
  final ValueChanged<String> onPeriod;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: DepthCard(
        soft: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: DropdownButton<int>(
                value: classId,
                hint: const Text('Sin clases'),
                underline: const SizedBox.shrink(),
                isExpanded: true,
                items: [
                  for (final c in classes)
                    DropdownMenuItem(
                      value: c.classId,
                      child: Text(
                        '${c.subjectName} · ${c.groupName}',
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleSmall,
                      ),
                    ),
                ],
                onChanged: classes.isEmpty
                    ? null
                    : (v) {
                        if (v != null) onClass(v);
                      },
              ),
            ),
            const SizedBox(width: 12),
            if (periods.isNotEmpty)
              DropdownButton<String>(
                value: periodId,
                underline: const SizedBox.shrink(),
                items: [
                  for (final p in periods)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        p.name,
                        style: context.textTheme.titleSmall
                            ?.copyWith(color: palette.accentDeep),
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onPeriod(v);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _GradebookBody extends ConsumerWidget {
  const _GradebookBody({
    required this.classesLoading,
    required this.periodsLoading,
    required this.hasClasses,
    required this.hasPeriods,
    required this.data,
    required this.scaleAsync,
    required this.args,
  });

  final bool classesLoading;
  final bool periodsLoading;
  final bool hasClasses;
  final bool hasPeriods;
  final AsyncValue<GradebookMatrix>? data;
  final AsyncValue<GradingScale?> scaleAsync;
  final GradebookArgs? args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (classesLoading || periodsLoading) return const SkeletonList();
    if (!hasClasses) {
      return const EmptyState(
        icon: Icons.school_rounded,
        title: 'Sin clases',
        subtitle: 'Asigna clases al maestro para usar el libro de notas.',
      );
    }
    if (!hasPeriods) {
      return const EmptyState(
        icon: Icons.calendar_month_rounded,
        title: 'Sin períodos académicos',
        subtitle: 'Crea un período académico para registrar calificaciones.',
      );
    }
    final data = this.data;
    final args = this.args;
    if (data == null || args == null) return const SkeletonList();
    return data.when(
      loading: () => const SkeletonList(),
      error: (e, _) => ErrorStateView(
        message: 'No se pudo cargar el libro de notas. Intenta nuevamente.',
        onRetry: () => ref.invalidate(gradebookProvider(args)),
      ),
      data: (matrix) {
        if (matrix.evaluations.isEmpty) {
          return const EmptyState(
            icon: Icons.assessment_rounded,
            title: 'Sin evaluaciones',
            subtitle: 'Crea una tarea o examen para calificar aquí.',
          );
        }
        return scaleAsync.when(
          loading: () => const SkeletonList(),
          error: (e, _) => ErrorStateView(
            message:
                'No se pudo cargar la escala de calificación. Intenta nuevamente.',
            onRetry: () => ref.invalidate(gradebookScaleProvider),
          ),
          data: (scale) => scale == null
              ? const EmptyState(
                  icon: Icons.assessment_outlined,
                  title: 'Sin escala de calificación',
                  subtitle:
                      'Solicita a la administración configurar una escala para tu institución. Se aplicará a todos los períodos.',
                )
              : _Matrix(
                  matrix: matrix,
                  scale: scale,
                  args: args,
                ),
        );
      },
    );
  }
}

class _Matrix extends ConsumerWidget {
  const _Matrix({
    required this.matrix,
    required this.scale,
    required this.args,
  });

  final GradebookMatrix matrix;
  final GradingScale scale;
  final GradebookArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Promedio de clase (normalizado a la escala) y avance de captura.
    var sum = 0.0;
    var graded = 0;
    final total = matrix.students.length * matrix.evaluations.length;
    for (final s in matrix.students) {
      for (final e in matrix.evaluations) {
        final raw = matrix.grades[s.studentId]?[e.id];
        if (raw != null) {
          sum += scale.normalize(raw, rawMax: e.maxScore);
          graded++;
        }
      }
    }
    final average = graded == 0 ? 0.0 : sum / graded;
    final completion = total == 0 ? 0.0 : graded / total;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      child: Column(
        children: [
          _ClassSummary(
            average: average,
            completion: completion,
            graded: graded,
            total: total,
            scale: scale,
          ),
          const SizedBox(height: 12),
          for (final s in matrix.students)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DepthCard(
                soft: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        UserAvatar(name: s.name, size: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s.name,
                            style: context.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in matrix.evaluations)
                          _EvaluationCell(
                            evaluation: e,
                            score: matrix.grades[s.studentId]?[e.id],
                            scale: scale,
                            onTap: ref.watch(classPermissionProvider(
                                    (args.classId, 'grades.write'),),)
                                ? () => _openEditor(
                                      context: context,
                                      ref: ref,
                                      evaluation: e,
                                      studentId: s.studentId,
                                      existing: matrix.grades[s.studentId]
                                          ?[e.id],
                                    )
                                : null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openEditor({
    required BuildContext context,
    required WidgetRef ref,
    required Evaluation evaluation,
    required int studentId,
    required double? existing,
  }) async {
    final ctrl = TextEditingController(
      text: existing?.toStringAsFixed(1) ?? '',
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassSurface(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              evaluation.title,
              style: Theme.of(ctx)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    'Puntaje sobre ${evaluation.maxScore.toStringAsFixed(0)}',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                final n = double.tryParse(ctrl.text);
                if (n == null) return;
                final clamped = n.clamp(0, evaluation.maxScore).toDouble();
                await ref.read(gradebookSaverProvider).setGrade(
                      evaluationId: evaluation.id,
                      studentId: studentId,
                      rawScore: clamped,
                      args: args,
                    );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassSummary extends StatelessWidget {
  const _ClassSummary({
    required this.average,
    required this.completion,
    required this.graded,
    required this.total,
    required this.scale,
  });

  final double average;
  final double completion;
  final int graded;
  final int total;
  final GradingScale scale;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pct = (completion * 100).round();
    return DepthCard(
      accent: palette.accent,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Promedio de clase',
                  style: context.textTheme.labelMedium?.copyWith(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedCount(
                  value: average,
                  decimals: 1,
                  suffix: ' / ${scale.maxValue.toStringAsFixed(0)}',
                  style: context.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: palette.accentDeep,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Captura',
                style: context.textTheme.labelMedium?.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$pct%',
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '$graded / $total notas',
                style: context.textTheme.labelSmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EvaluationCell extends StatelessWidget {
  const _EvaluationCell({
    required this.evaluation,
    required this.score,
    required this.scale,
    required this.onTap,
  });

  final Evaluation evaluation;
  final double? score;
  final GradingScale scale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              evaluation.title,
              style: context.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            if (score == null)
              Icon(Icons.add, size: 16, color: palette.accentDeep)
            else
              GradePill(
                score: scale.normalize(score!, rawMax: evaluation.maxScore),
                scale: scale,
                dense: true,
                showLabel: false,
              ),
          ],
        ),
      ),
    );
  }
}
