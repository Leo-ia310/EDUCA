import '../../../collaborations/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/provider_cache.dart';

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
import '../../domain/gradebook_stats.dart';
import '../../domain/grades_repository.dart';
import '../../providers.dart';
import '../controllers/gradebook_controller.dart';

enum _Sort {
  name('Nombre'),
  best('Mayor promedio'),
  worst('Menor promedio');

  const _Sort(this.label);
  final String label;
}

/// Libro de notas del docente: por periodo o acumulado del año hasta hoy.
/// Una tarjeta por estudiante con su promedio, estado y todas sus notas.
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
    final periods = _uniquePeriods(periodsAsync.scopedValue ?? const []);
    final classes = (classesAsync.scopedValue ?? const <ClassSessionBrief>[])
        .where((c) => c.can('students.view'))
        .toList();
    final selectedClassId = classes.any((c) => c.classId == _classId)
        ? _classId
        : classes.isEmpty
            ? null
            : classes.first.classId;
    final selectedPeriodId = _periodId == kGradebookYear && periods.isNotEmpty
        ? kGradebookYear
        : periods.any((p) => p.id == _periodId)
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
                classesLoading:
                    classesAsync.isLoading && !classesAsync.isRefreshing,
                periodsLoading:
                    periodsAsync.isLoading && !periodsAsync.isRefreshing,
                hasClasses: classes.isNotEmpty,
                hasPeriods: periods.isNotEmpty,
                data: data,
                scaleAsync: scaleAsync,
                args: args,
                periods: periods,
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

/// Color de una nota según el rango de la escala (o aprobado/reprobado).
Color _scoreColor(BuildContext context, GradingScale scale, double value) {
  final palette = context.palette;
  for (final r in scale.ranges) {
    if (r.contains(value) && r.color != null) return r.color!;
  }
  return scale.isPassing(value) ? palette.success : palette.danger;
}

/// Texto de una nota: la etiqueta en escalas cualitativas, el número si no.
String _scoreText(GradingScale scale, double value) {
  if (scale.type == ScaleType.qualitative) {
    return scale.labelFor(value) ?? value.toStringAsFixed(scale.decimals);
  }
  return value.toStringAsFixed(scale.decimals);
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.class_rounded, size: 18, color: palette.accentDeep),
                const SizedBox(width: 8),
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
                            style: context.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
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
              ],
            ),
            Divider(height: 1, color: palette.textMuted.withValues(alpha: 0.25)),
            Row(
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  size: 18,
                  color: palette.accentDeep,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: periods.isEmpty
                      ? const SizedBox(height: 48)
                      : DropdownButton<String>(
                          value: periodId,
                          underline: const SizedBox.shrink(),
                          isExpanded: true,
                          items: [
                            DropdownMenuItem(
                              value: kGradebookYear,
                              child: Text(
                                'Año completo (hasta hoy)',
                                style: context.textTheme.titleSmall?.copyWith(
                                  color: palette.accentDeep,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
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
                ),
              ],
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
    required this.periods,
  });

  final bool classesLoading;
  final bool periodsLoading;
  final bool hasClasses;
  final bool hasPeriods;
  final AsyncValue<GradebookMatrix>? data;
  final AsyncValue<GradingScale?> scaleAsync;
  final GradebookArgs? args;
  final List<AcademicPeriod> periods;

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
        final yearMode = args.periodId == kGradebookYear;
        final shown = visibleEvaluations(matrix, yearMode: yearMode);
        if (shown.isEmpty) {
          return EmptyState(
            icon: Icons.assessment_rounded,
            title: 'Sin evaluaciones',
            subtitle: yearMode
                ? 'Aún no hay evaluaciones registradas este año.'
                : 'Crea una tarea o examen para calificar aquí.',
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
                  evaluations: shown,
                  scale: scale,
                  args: args,
                  periods: periods,
                  yearMode: yearMode,
                ),
        );
      },
    );
  }
}

class _Matrix extends ConsumerStatefulWidget {
  const _Matrix({
    required this.matrix,
    required this.evaluations,
    required this.scale,
    required this.args,
    required this.periods,
    required this.yearMode,
  });

  final GradebookMatrix matrix;
  final List<Evaluation> evaluations;
  final GradingScale scale;
  final GradebookArgs args;
  final List<AcademicPeriod> periods;
  final bool yearMode;

  @override
  ConsumerState<_Matrix> createState() => _MatrixState();
}

class _MatrixState extends ConsumerState<_Matrix> {
  String _query = '';
  _Sort _sort = _Sort.name;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final canEdit = ref.watch(
      classPermissionProvider((w.args.classId, 'grades.write')),
    );
    final summaries = summarizeStudents(
      matrix: w.matrix,
      evaluations: w.evaluations,
      scale: w.scale,
      yearMode: w.yearMode,
      periods: w.periods,
    );
    final periodNames = {for (final p in w.periods) p.id: p.name};

    var list = summaries.where((s) {
      final q = _query.trim().toLowerCase();
      return q.isEmpty || s.name.toLowerCase().contains(q);
    }).toList();
    int cmp(StudentGradeSummary a, StudentGradeSummary b) {
      final x = a.average, y = b.average;
      if (x == null && y == null) return a.name.compareTo(b.name);
      if (x == null) return 1;
      if (y == null) return -1;
      return _sort == _Sort.best ? y.compareTo(x) : x.compareTo(y);
    }

    if (_sort != _Sort.name) list = [...list]..sort(cmp);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: list.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ClassSummary(
                summaries: summaries,
                scale: w.scale,
                evaluationCount: w.evaluations.length,
                yearMode: w.yearMode,
              ),
              const SizedBox(height: 12),
              _Tools(
                sort: _sort,
                onQuery: (v) => setState(() => _query = v),
                onSort: (v) => setState(() => _sort = v),
              ),
              const SizedBox(height: 12),
            ],
          );
        }
        if (i == list.length + 1) {
          return list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Ningún estudiante coincide con la búsqueda.',
                      style: context.textTheme.bodyMedium
                          ?.copyWith(color: context.palette.textMuted),
                    ),
                  ),
                )
              : const SizedBox.shrink();
        }
        final s = list[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _StudentCard(
            summary: s,
            evaluations: w.evaluations,
            grades: w.matrix.grades[s.studentId] ?? const {},
            scale: w.scale,
            periodNames: w.yearMode ? periodNames : const {},
            onEdit: canEdit
                ? (e) => _openEditor(
                      context: context,
                      ref: ref,
                      evaluation: e,
                      studentName: s.name,
                      studentId: s.studentId,
                      existing: w.matrix.grades[s.studentId]?[e.id],
                    )
                : null,
          ),
        );
      },
    );
  }

  Future<void> _openEditor({
    required BuildContext context,
    required WidgetRef ref,
    required Evaluation evaluation,
    required String studentName,
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
            const SizedBox(height: 2),
            Text(
              studentName,
              style: Theme.of(ctx)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: context.palette.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
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
                      args: widget.args,
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

/// Resumen de la clase: promedio, aprobados/en riesgo y avance de captura.
class _ClassSummary extends StatelessWidget {
  const _ClassSummary({
    required this.summaries,
    required this.scale,
    required this.evaluationCount,
    required this.yearMode,
  });

  final List<StudentGradeSummary> summaries;
  final GradingScale scale;
  final int evaluationCount;
  final bool yearMode;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final withAvg = [
      for (final s in summaries)
        if (s.average != null) s.average!,
    ];
    final average = withAvg.isEmpty
        ? null
        : withAvg.reduce((a, b) => a + b) / withAvg.length;
    final passing = withAvg.where(scale.isPassing).length;
    final atRisk = withAvg.length - passing;
    final graded = summaries.fold<int>(0, (a, s) => a + s.gradedCount);
    final total = summaries.length * evaluationCount;
    final completion = total == 0 ? 0.0 : graded / total;
    final avgColor = average == null
        ? palette.textMuted
        : _scoreColor(context, scale, average);

    Widget stat(String value, String label, Color color) => Expanded(
          child: Column(
            children: [
              Text(
                value,
                style: context.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800, color: color),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: context.textTheme.labelSmall
                    ?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        );

    return DepthCard(
      accent: palette.accent,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                yearMode ? Icons.timeline_rounded : Icons.insights_rounded,
                size: 16,
                color: palette.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                yearMode
                    ? 'Promedio acumulado del año'
                    : 'Promedio de la clase',
                style: context.textTheme.labelMedium?.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (average == null)
            Text(
              'Sin notas aún',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: palette.textMuted,
              ),
            )
          else
            AnimatedCount(
              value: average,
              decimals: scale.decimals,
              suffix: ' / ${scale.maxValue.toStringAsFixed(0)}',
              style: context.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: avgColor,
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              stat('$passing', 'Aprobados', palette.success),
              stat('$atRisk', 'En riesgo', palette.danger),
              stat('${summaries.length}', 'Estudiantes', palette.accentDeep),
              stat('$evaluationCount', 'Evaluaciones', palette.accentDeep),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Captura de notas',
                style: context.textTheme.labelMedium
                    ?.copyWith(color: palette.textMuted),
              ),
              const Spacer(),
              Text(
                '$graded / $total · ${(completion * 100).round()} %',
                style: context.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: completion.clamp(0.0, 1.0),
              minHeight: 8,
              color: palette.accentDeep,
              backgroundColor: palette.accentDeep.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}

/// Búsqueda por nombre y orden de la lista.
class _Tools extends StatelessWidget {
  const _Tools({
    required this.sort,
    required this.onQuery,
    required this.onSort,
  });

  final _Sort sort;
  final ValueChanged<String> onQuery;
  final ValueChanged<_Sort> onSort;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: onQuery,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Buscar estudiante',
            prefixIcon: Icon(Icons.search_rounded),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in _Sort.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s.label),
                    selected: sort == s,
                    onSelected: (_) => onSort(s),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tarjeta de un estudiante: encabezado con promedio y estado, y cuadrícula
/// de notas (una celda por evaluación, con el nombre completo visible).
class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.summary,
    required this.evaluations,
    required this.grades,
    required this.scale,
    required this.periodNames,
    required this.onEdit,
  });

  final StudentGradeSummary summary;
  final List<Evaluation> evaluations;
  final Map<String, double?> grades;
  final GradingScale scale;
  final Map<String, String> periodNames;
  final void Function(Evaluation)? onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final avg = summary.average;
    final color =
        avg == null ? palette.textMuted : _scoreColor(context, scale, avg);
    final passing = avg != null && scale.isPassing(avg);
    final status = avg == null
        ? 'Sin notas'
        : scale.type == ScaleType.qualitative
            ? (scale.labelFor(avg) ?? '')
            : passing
                ? 'Aprobado'
                : 'En riesgo';

    String? detail;
    if (summary.gradedCount > 0) {
      detail = '${summary.gradedCount}/${summary.totalCount} notas · '
          'Mejor ${_scoreText(scale, summary.best!)} · '
          'Más baja ${_scoreText(scale, summary.worst!)}';
    } else {
      detail = '0/${summary.totalCount} notas';
    }

    return DepthCard(
      soft: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: summary.name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    avg == null ? '—' : _scoreText(scale, avg),
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      status,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (avg != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(
                value: ((avg - scale.minValue) /
                        (scale.maxValue - scale.minValue == 0
                            ? 1
                            : scale.maxValue - scale.minValue))
                    .clamp(0.0, 1.0),
                minHeight: 6,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final tileWidth = (c.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in evaluations)
                    SizedBox(
                      width: tileWidth,
                      child: _GradeTile(
                        evaluation: e,
                        score: grades[e.id],
                        scale: scale,
                        caption: periodNames[e.periodId],
                        onTap: onEdit == null ? null : () => onEdit!(e),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Celda de una evaluación: título completo, nota coloreada y nota cruda.
class _GradeTile extends StatelessWidget {
  const _GradeTile({
    required this.evaluation,
    required this.score,
    required this.scale,
    required this.caption,
    required this.onTap,
  });

  final Evaluation evaluation;
  final double? score;
  final GradingScale scale;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final s = score;
    final normalized =
        s == null ? null : scale.normalize(s, rawMax: evaluation.maxScore);
    final color = normalized == null
        ? palette.textMuted
        : _scoreColor(context, scale, normalized);
    final sameMax = evaluation.maxScore == scale.maxValue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: normalized == null
                ? palette.surfaceAlt
                : color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border(
              left: BorderSide(
                color: normalized == null ? palette.textMuted.withValues(alpha: 0.25) : color,
                width: 4,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                evaluation.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.textMuted,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: palette.textMuted.withValues(alpha: 0.8),
                    fontSize: 10,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (normalized == null) ...[
                    Icon(
                      onTap == null ? Icons.remove_rounded : Icons.add_rounded,
                      size: 18,
                      color: palette.accentDeep,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      onTap == null ? 'Sin nota' : 'Calificar',
                      style: context.textTheme.labelMedium?.copyWith(
                        color: palette.accentDeep,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else ...[
                    Text(
                      _scoreText(scale, normalized),
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    if (!sameMax && scale.type != ScaleType.qualitative) ...[
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '${s!.toStringAsFixed(s % 1 == 0 ? 0 : 1)}/${evaluation.maxScore.toStringAsFixed(0)}',
                          style: context.textTheme.labelSmall
                              ?.copyWith(color: palette.textMuted),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
