import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../attendance/data/mock_attendance_data.dart';
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
  int _classId = 101;
  String _periodId = 'p2';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final args = GradebookArgs(classId: _classId, periodId: _periodId);
    final data = ref.watch(gradebookProvider(args));
    final scaleAsync = ref.watch(defaultScaleProvider);
    final periodsAsync = ref.watch(periodsProvider);

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Libro de notas'),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Filters(
              classId: _classId,
              periodId: _periodId,
              periodsAsync: periodsAsync,
              onClass: (v) => setState(() => _classId = v),
              onPeriod: (v) => setState(() => _periodId = v),
            ),
            Expanded(
              child: data.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (matrix) {
                  if (matrix.evaluations.isEmpty) {
                    return const EmptyState(
                      icon: Icons.assessment_outlined,
                      title: 'Sin evaluaciones',
                      subtitle:
                          'Crea una tarea o examen para calificar aquí.',
                    );
                  }
                  return scaleAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ErrorStateView(message: '$e'),
                    data: (scale) => _Matrix(
                      matrix: matrix,
                      scale: scale,
                      args: args,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.classId,
    required this.periodId,
    required this.periodsAsync,
    required this.onClass,
    required this.onPeriod,
  });

  final int classId;
  final String periodId;
  final AsyncValue<List<AcademicPeriod>> periodsAsync;
  final ValueChanged<int> onClass;
  final ValueChanged<String> onPeriod;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: EduCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: DropdownButton<int>(
                value: classId,
                underline: const SizedBox.shrink(),
                isExpanded: true,
                items: [
                  for (final c in AttendanceMock.todaysClasses)
                    DropdownMenuItem(
                      value: c.classId,
                      child: Text(
                        '${c.subjectName} · ${c.groupName}',
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleSmall,
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onClass(v);
                },
              ),
            ),
            const SizedBox(width: 12),
            periodsAsync.maybeWhen(
              data: (list) => DropdownButton<String>(
                value: periodId,
                underline: const SizedBox.shrink(),
                items: [
                  for (final p in list)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name,
                          style: context.textTheme.titleSmall
                              ?.copyWith(color: palette.limeDeep)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onPeriod(v);
                },
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
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
    final palette = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      child: Column(
        children: [
          for (final s in matrix.students)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: EduCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
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
                            onTap: () => _openEditor(
                              context: context,
                              ref: ref,
                              evaluation: e,
                              studentId: s.studentId,
                              existing:
                                  matrix.grades[s.studentId]?[e.id],
                            ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
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
            Text(evaluation.title,
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              decoration: InputDecoration(
                labelText: 'Puntaje sobre ${evaluation.maxScore.toStringAsFixed(0)}',
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
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
              Icon(Icons.add, size: 16, color: palette.limeDeep)
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
