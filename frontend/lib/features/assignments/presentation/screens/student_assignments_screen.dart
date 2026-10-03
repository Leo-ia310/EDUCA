import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/entrance.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../dashboard/data/dashboard_data.dart';
import '../../../dashboard/domain/dashboard_models.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../../dashboard/providers.dart';
import '../../domain/entities.dart';
import '../controllers/assignment_detail_controller.dart';
import '../controllers/assignments_list_controller.dart';
import '../widgets/assignment_card.dart';

/// Solo tareas: los exámenes/quizzes viven en "Mis pruebas".
List<Assignment> _tasksOnly(List<Assignment> all) => all
    .where(
      (a) => a.kind != AssignmentKind.exam && a.kind != AssignmentKind.quiz,
    )
    .toList();

/// Entregada = hay una entrega registrada (no pendiente).
bool _delivered(WidgetRef ref, Assignment a, int studentId) {
  final st = ref
      .watch(
        mySubmissionProvider((assignmentId: a.id, studentId: studentId)),
      )
      .asData
      ?.value
      ?.status;
  return st != null && st != SubmissionStatus.pending;
}

/// Coincidencia flexible entre el nombre de la materia del alumno
/// ("Matemáticas") y el de la tarea ("Matemáticas Avanzadas").
bool _sameSubject(String a, String b) {
  final x = a.toLowerCase().trim();
  final y = b.toLowerCase().trim();
  return x == y || x.contains(y) || y.contains(x);
}

/// Secciones Pendientes y Entregadas de un conjunto de tareas.
List<Widget> _sections(
  BuildContext context,
  WidgetRef ref,
  List<Assignment> items,
  int studentId,
) {
  final pending = items.where((a) => !_delivered(ref, a, studentId)).toList();
  final done = items.where((a) => _delivered(ref, a, studentId)).toList();
  var entranceIndex = 0;

  Widget section(String title, List<Assignment> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, accent: false),
          const SizedBox(height: 8),
          for (final a in list)
            entranceItem(
              context,
              entranceIndex++,
              _StudentTile(
                assignment: a,
                studentId: studentId,
                onTap: () => context.push('${Routes.assignments}/${a.id}'),
              ),
            ),
        ],
      );

  return [
    if (pending.isNotEmpty) ...[
      section('Pendientes', pending),
      const SizedBox(height: 16),
    ],
    if (done.isNotEmpty) section('Entregadas', done),
  ];
}

/// Feed de tareas para estudiante y padre, con dos vistas: "Por materia"
/// (tarjetas de materias que abren su propio panel) y "Vista general" (todas
/// las tareas por fecha de entrega). El `studentId` es el del estudiante
/// observado.
class StudentAssignmentsScreen extends ConsumerStatefulWidget {
  const StudentAssignmentsScreen({super.key, required this.studentId});
  final int studentId;

  @override
  ConsumerState<StudentAssignmentsScreen> createState() =>
      _StudentAssignmentsScreenState();
}

class _StudentAssignmentsScreenState
    extends ConsumerState<StudentAssignmentsScreen> {
  bool _bySubject = true;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(studentAssignmentsProvider);
    final palette = context.palette;

    return StudentDetailScaffold(
      title: 'Mis tareas',
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _ModePill(
                      label: 'Por materia',
                      selected: _bySubject,
                      onTap: () => setState(() => _bySubject = true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModePill(
                      label: 'Vista general',
                      selected: !_bySubject,
                      onTap: () => setState(() => _bySubject = false),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: crossfadeState(
                context,
                list.when(
                  loading: () => const SkeletonList(),
                  error: (e, _) => ErrorStateView(message: '$e'),
                  data: (allItems) {
                    final items = _tasksOnly(allItems);
                    if (items.isEmpty) {
                      return EmptyState(
                        icon: Icons.task_alt_rounded,
                        title: 'Todo al día',
                        subtitle:
                            'No tienes tareas asignadas en este momento.',
                        actionLabel: 'Ver horario',
                        onAction: () => context.go(Routes.schedule),
                      );
                    }
                    return RefreshIndicator(
                      color: palette.accentDeep,
                      onRefresh: () async =>
                          ref.invalidate(studentAssignmentsProvider),
                      child: ListView(
                        key: ValueKey(_bySubject),
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                        children: _bySubject
                            ? _subjectCards(context, items)
                            : _generalList(context, items),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Vista general: todas las tareas, por fecha de entrega.
  List<Widget> _generalList(BuildContext context, List<Assignment> items) {
    final sorted = [...items]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return [
      for (final (i, a) in sorted.indexed)
        entranceItem(
          context,
          i,
          _StudentTile(
            assignment: a,
            studentId: widget.studentId,
            onTap: () => context.push('${Routes.assignments}/${a.id}'),
          ),
        ),
    ];
  }

  /// Por materia: una tarjeta por cada materia del estudiante.
  List<Widget> _subjectCards(BuildContext context, List<Assignment> items) {
    final subjects =
        ref.watch(studentDashboardProvider).valueOrNull?.subjects ??
            StudentDashboardData.mock().subjects;
    return [
      for (final (i, s) in subjects.indexed)
        entranceItem(
          context,
          i,
          _SubjectCard(
            subject: s,
            tasks: items
                .where((a) => _sameSubject(a.subjectName, s.name))
                .toList(),
            studentId: widget.studentId,
            onTap: () => context.push(
              '${Routes.assignments}/subject/${Uri.encodeComponent(s.name)}',
            ),
          ),
        ),
    ];
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.accentDeep : palette.cardElevated,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
            color:
                selected ? palette.accentDeep : Theme.of(context).dividerColor,
          ),
        ),
        child: Text(
          label,
          style: context.textTheme.labelLarge?.copyWith(
            color: selected ? Colors.white : palette.textMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de una materia: ícono, nombre y conteo de pendientes.
class _SubjectCard extends ConsumerWidget {
  const _SubjectCard({
    required this.subject,
    required this.tasks,
    required this.studentId,
    required this.onTap,
  });

  final SubjectProgress subject;
  final List<Assignment> tasks;
  final int studentId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.pastel(subject.color ?? subjectColor(subject.name));
    final pending = tasks.where((a) => !_delivered(ref, a, studentId)).length;
    final summary = tasks.isEmpty
        ? 'Sin tareas'
        : pending == 0
            ? 'Todo entregado'
            : '$pending pendiente${pending == 1 ? '' : 's'}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.lg),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: s.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration:
                      BoxDecoration(color: s.vivid, shape: BoxShape.circle),
                  child: Icon(
                    subject.icon ?? Icons.menu_book_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleMedium?.copyWith(
                          color: s.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        summary,
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: s.inkMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.black,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel de una materia: sus tareas, en Pendientes y Entregadas.
class SubjectAssignmentsScreen extends ConsumerWidget {
  const SubjectAssignmentsScreen({
    super.key,
    required this.studentId,
    required this.subject,
  });

  final int studentId;
  final String subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(studentAssignmentsProvider);
    return StudentDetailScaffold(
      title: subject,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: crossfadeState(
          context,
          list.when(
            loading: () => const SkeletonList(),
            error: (e, _) => ErrorStateView(message: '$e'),
            data: (all) {
              final items = _tasksOnly(all)
                  .where((a) => _sameSubject(a.subjectName, subject))
                  .toList();
              if (items.isEmpty) {
                return const EmptyState(
                  icon: Icons.task_alt_rounded,
                  title: 'Sin tareas',
                  subtitle: 'No hay tareas asignadas en esta materia.',
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
                children: _sections(context, ref, items, studentId),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StudentTile extends ConsumerWidget {
  const _StudentTile({
    required this.assignment,
    required this.studentId,
    required this.onTap,
  });

  final Assignment assignment;
  final int studentId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(mySubmissionProvider(
        (assignmentId: assignment.id, studentId: studentId),),);
    final status = mine.asData?.value?.status;
    final score = mine.asData?.value?.score;
    final done = ref.watch(tasksDoneProvider).contains(assignment.id);
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        key: ValueKey(assignment.id),
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: 0.28,
          children: [
            SlidableAction(
              onPressed: (_) =>
                  ref.read(tasksDoneProvider.notifier).toggle(assignment.id),
              backgroundColor: done ? palette.textMuted : palette.success,
              foregroundColor: Colors.white,
              icon: done ? Icons.undo_rounded : Icons.check_circle_outline,
              label: done ? 'Pendiente' : 'Hecha',
              borderRadius: BorderRadius.circular(Radii.md),
            ),
          ],
        ),
        child: AnimatedOpacity(
          opacity: done ? 0.5 : 1,
          duration: const Duration(milliseconds: 200),
          child: AssignmentCard(
            assignment: assignment,
            onTap: onTap,
            showProgress: false,
            studentStatus: status,
            studentScore: score,
            pastel: true,
          ),
        ),
      ),
    );
  }
}
