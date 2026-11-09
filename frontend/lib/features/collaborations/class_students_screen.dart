import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/plural.dart';
import '../../core/widgets/brutal.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/user_avatar.dart';
import '../dashboard/data/class_insights.dart';
import '../dashboard/presentation/widgets/student_chrome.dart';
import 'providers.dart';

/// Falla si el docente no puede ver a los estudiantes de la clase (un
/// colaborador sin ese permiso).
final _studentsAccessProvider =
    FutureProvider.autoDispose.family<void, int>((ref, classId) async {
  final allowed = await ref.watch(collaborationWorkspaceProvider.future);
  final ok = (allowed['classes'] as List).any(
    (c) =>
        c['classId'] == classId &&
        (c['permissions'] as List).contains('students.view'),
  );
  if (!ok) {
    throw StateError(
        'No tienes permiso para ver los estudiantes de esta clase.',);
  }
});

enum _Sort { name, attention }

/// Estudiantes de una clase con su asistencia y promedio: quién va bien y a
/// quién conviene prestarle atención.
class ClassStudentsScreen extends ConsumerStatefulWidget {
  const ClassStudentsScreen({super.key, required this.classId, this.className});
  final int classId;
  final String? className;

  @override
  ConsumerState<ClassStudentsScreen> createState() =>
      _ClassStudentsScreenState();
}

class _ClassStudentsScreenState extends ConsumerState<ClassStudentsScreen> {
  String _query = '';
  _Sort _sort = _Sort.name;

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(_studentsAccessProvider(widget.classId));
    final insights = ref.watch(classInsightsProvider(widget.classId));

    Widget body;
    if (access.hasError) {
      body = ErrorStateView(
        message: '${access.error}'.replaceFirst('Bad state: ', ''),
        onRetry: () => ref.invalidate(_studentsAccessProvider(widget.classId)),
      );
    } else if (access.isLoading || insights.isLoading) {
      body = const SkeletonList();
    } else if (insights.hasError) {
      body = ErrorStateView(
        message: 'No se pudieron cargar los estudiantes.',
        onRetry: () => ref.invalidate(classInsightsProvider(widget.classId)),
      );
    } else {
      final data = insights.requireValue;
      body = data.students.isEmpty
          ? const EmptyState(
              icon: Icons.group_outlined,
              title: 'Sin estudiantes',
              subtitle: 'Esta clase todavía no tiene estudiantes matriculados.',
            )
          : _Content(
              data: data,
              className: widget.className,
              query: _query,
              sort: _sort,
              onQuery: (v) => setState(() => _query = v),
              onSort: (v) => setState(() => _sort = v),
            );
    }

    return StudentDetailScaffold(
      title: 'Estudiantes',
      bottomNav: false,
      onRefresh: () async {
        ref.invalidate(classInsightsProvider(widget.classId));
        await ref.read(classInsightsProvider(widget.classId).future);
      },
      child: body,
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.data,
    required this.className,
    required this.query,
    required this.sort,
    required this.onQuery,
    required this.onSort,
  });

  final ClassInsights data;
  final String? className;
  final String query;
  final _Sort sort;
  final ValueChanged<String> onQuery;
  final ValueChanged<_Sort> onSort;

  List<StudentInsight> _visible() {
    final q = query.trim().toLowerCase();
    final list = [
      for (final s in data.students)
        if (q.isEmpty ||
            s.fullName.toLowerCase().contains(q) ||
            (s.code ?? '').toLowerCase().contains(q))
          s,
    ];
    if (sort == _Sort.attention) {
      // En riesgo primero; dentro de cada grupo, de menor a mayor asistencia.
      double key(StudentInsight s) => s.attendanceRate ?? 2;
      list.sort((a, b) {
        if (a.atRisk != b.atRisk) return a.atRisk ? -1 : 1;
        final byRate = key(a).compareTo(key(b));
        return byRate != 0
            ? byRate
            : a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final visible = _visible();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Summary(data: data, className: className),
        const SizedBox(height: 16),
        TextField(
          onChanged: onQuery,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar por nombre o código',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => onQuery(''),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _SortChip(
              label: 'A–Z',
              icon: Icons.sort_by_alpha_rounded,
              selected: sort == _Sort.name,
              onTap: () => onSort(_Sort.name),
            ),
            const SizedBox(width: 8),
            _SortChip(
              label: 'Atención primero',
              icon: Icons.priority_high_rounded,
              selected: sort == _Sort.attention,
              onTap: () => onSort(_Sort.attention),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'Ningún estudiante coincide con «$query».',
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: palette.textMuted),
              ),
            ),
          )
        else
          for (final s in visible) ...[
            _StudentCard(
              student: s,
              hasAttendance: data.attendanceRate != null,
              hasGrades: data.gradeAverage != null,
              onTap: () => _showDetail(context, s),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  void _showDetail(BuildContext context, StudentInsight s) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StudentSheet(student: s),
    );
  }
}

/// Resumen de la clase: cuántos son, asistencia y promedio, y cuántos en riesgo.
class _Summary extends StatelessWidget {
  const _Summary({required this.data, required this.className});
  final ClassInsights data;
  final String? className;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final rate = data.attendanceRate;
    final avg = data.gradeAverage;
    return BrutalBox(
      radius: Radii.lg,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [palette.accent, palette.accentDeep],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plural(data.students.length, 'estudiante'),
                      style: context.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (className != null && className!.isNotEmpty)
                      Text(
                        className!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _SummaryStat(
                icon: Icons.how_to_reg_rounded,
                value: rate == null ? '—' : '${(rate * 100).round()}%',
                label: 'Asistencia',
              ),
              const SizedBox(width: 8),
              _SummaryStat(
                icon: Icons.grade_rounded,
                value: avg == null ? '—' : avg.round().toString(),
                label: 'Promedio',
              ),
              const SizedBox(width: 8),
              _SummaryStat(
                icon: Icons.warning_amber_rounded,
                value: '${data.atRiskCount}',
                label: 'En riesgo',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: context.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: context.textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.88),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = selected ? Colors.white : palette.accentDeep;
    return Material(
      color: selected ? palette.accentDeep : palette.accentSoft,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _attendanceColor(AppPalette p, double rate) => rate >= 0.9
    ? p.success
    : rate >= lowAttendance
        ? p.warning
        : p.danger;

Color _gradeColor(AppPalette p, double avg) => avg >= 80
    ? p.success
    : avg >= passGrade
        ? p.warning
        : p.danger;

class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.student,
    required this.hasAttendance,
    required this.hasGrades,
    required this.onTap,
  });
  final StudentInsight student;
  final bool hasAttendance;
  final bool hasGrades;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final rate = student.attendanceRate;
    final avg = student.gradeAverage;
    return BrutalBox(
      onTap: onTap,
      color: context.paper,
      radius: Radii.lg,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: student.fullName, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: context.onPaper,
                      ),
                    ),
                    if ((student.code ?? '').isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.badge_outlined,
                            size: 14,
                            color: palette.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              student.code!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.bodySmall
                                  ?.copyWith(color: palette.textMuted),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (student.atRisk)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: palette.danger.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: palette.danger,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Atención',
                        style: context.textTheme.labelSmall?.copyWith(
                          color: palette.danger,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (hasAttendance || hasGrades) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (hasAttendance)
                  _MetricChip(
                    icon: Icons.how_to_reg_rounded,
                    text: rate == null
                        ? 'Sin asistencia'
                        : 'Asistencia ${(rate * 100).round()}%',
                    color: rate == null
                        ? palette.textMuted
                        : _attendanceColor(palette, rate),
                  ),
                if (hasGrades)
                  _MetricChip(
                    icon: Icons.grade_rounded,
                    text: avg == null ? 'Sin notas' : 'Promedio ${avg.round()}',
                    color: avg == null
                        ? palette.textMuted
                        : _gradeColor(palette, avg),
                  ),
                if (student.absent > 0)
                  _MetricChip(
                    icon: Icons.event_busy_rounded,
                    text: plural(student.absent, 'falta'),
                    color: palette.danger,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: context.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Detalle de un estudiante: desglose de asistencia y notas.
class _StudentSheet extends StatelessWidget {
  const _StudentSheet({required this.student});
  final StudentInsight student;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final rate = student.attendanceRate;
    final avg = student.gradeAverage;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                UserAvatar(name: student.fullName, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.fullName,
                        style: context.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if ((student.code ?? '').isNotEmpty)
                        Text(
                          'Código ${student.code}',
                          style: context.textTheme.bodySmall
                              ?.copyWith(color: palette.textMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SheetTitle(
              icon: Icons.how_to_reg_rounded,
              text: rate == null
                  ? 'Asistencia'
                  : 'Asistencia · ${(rate * 100).round()}%',
            ),
            const SizedBox(height: 10),
            if (student.sessions == 0)
              Text(
                'Todavía no hay asistencia registrada.',
                style: context.textTheme.bodySmall
                    ?.copyWith(color: palette.textMuted),
              )
            else
              Row(
                children: [
                  _Count(
                    value: student.present,
                    label: 'Presente',
                    color: palette.success,
                  ),
                  _Count(
                    value: student.late,
                    label: 'Tarde',
                    color: palette.warning,
                  ),
                  _Count(
                    value: student.absent,
                    label: 'Ausente',
                    color: palette.danger,
                  ),
                  _Count(
                    value: student.justified,
                    label: 'Justificada',
                    color: palette.info,
                  ),
                ],
              ),
            const SizedBox(height: 18),
            _SheetTitle(
              icon: Icons.grade_rounded,
              text: avg == null ? 'Notas' : 'Promedio · ${avg.round()}',
            ),
            const SizedBox(height: 6),
            Text(
              avg == null
                  ? 'Todavía no tiene evaluaciones calificadas.'
                  : '${plural(student.gradedCount, 'evaluación calificada', 'evaluaciones calificadas')} · '
                      '${avg >= passGrade ? 'aprueba' : 'por debajo de la nota mínima ($passGrade)'.replaceAll('.0', '')}',
              style: context.textTheme.bodySmall
                  ?.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Icon(icon, size: 18, color: palette.accentDeep),
        const SizedBox(width: 8),
        Text(
          text,
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label, required this.color});
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: context.textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: context.textTheme.labelSmall),
        ],
      ),
    );
  }
}
