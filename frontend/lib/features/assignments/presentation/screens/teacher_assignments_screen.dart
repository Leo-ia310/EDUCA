import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/entrance.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../dashboard/data/dashboard_data.dart';
import '../../../dashboard/data/mock_dashboard_data.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../../dashboard/providers.dart';
import '../../domain/entities.dart';
import '../controllers/assignments_list_controller.dart';
import '../widgets/assignment_card.dart';

/// Coincidencia flexible entre nombres de materia.
bool _sameSubject(String a, String b) {
  final x = a.toLowerCase().trim();
  final y = b.toLowerCase().trim();
  return x == y || x.contains(y) || y.contains(x);
}

/// Más reciente primero (fecha de creación).
List<Assignment> _byCreation(Iterable<Assignment> items) =>
    [...items]..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

/// Materias del docente: las de sus clases (con fallback a las que aparecen
/// en sus tareas si aún no tiene clases cargadas).
List<TeacherClass> _teacherSubjects(WidgetRef ref, List<Assignment> all) {
  final classes = (ref.watch(teacherDashboardProvider).valueOrNull ??
          TeacherDashboardData.mock())
      .myClasses;
  if (classes.isNotEmpty) return classes;
  final names = {for (final a in all) a.subjectName};
  return [
    for (final n in names)
      TeacherClass(name: n, room: '', icon: Icons.menu_book_rounded),
  ];
}

/// Panel "Tareas y Exámenes" del docente: "Por materia" (tarjetas de materia
/// que abren su propio panel) y "Vista general" (todo, por fecha de creación).
class TeacherAssignmentsScreen extends ConsumerStatefulWidget {
  const TeacherAssignmentsScreen({super.key});

  @override
  ConsumerState<TeacherAssignmentsScreen> createState() =>
      _TeacherAssignmentsScreenState();
}

class _TeacherAssignmentsScreenState
    extends ConsumerState<TeacherAssignmentsScreen> {
  bool _bySubject = true;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(teacherAssignmentsProvider);
    final palette = context.palette;

    return StudentDetailScaffold(
      title: 'Tareas y Exámenes',
      scrollable: false,
      bottomNav: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
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
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (r) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [Colors.transparent, Colors.black],
                  stops: [0, (28 / r.height).clamp(0.0, 1.0)],
                ).createShader(r),
                child: list.when(
                  loading: () => const SkeletonList(),
                  error: (e, _) => ErrorStateView(message: '$e'),
                  data: (all) {
                    final subjects = _teacherSubjects(ref, all);
                    final mine = subjects.isEmpty
                        ? all
                        : all
                            .where(
                              (a) => subjects.any(
                                (s) => _sameSubject(a.subjectName, s.name),
                              ),
                            )
                            .toList();
                    if (mine.isEmpty && subjects.isEmpty) {
                      return EmptyState(
                        icon: Icons.assignment_rounded,
                        title: 'Sin tareas aún',
                        subtitle: 'Crea tu primera tarea o examen.',
                        actionLabel: 'Crear tarea',
                        onAction: () =>
                            context.push('${Routes.assignments}/new'),
                      );
                    }
                    return RefreshIndicator(
                      color: palette.accentDeep,
                      onRefresh: () async =>
                          ref.invalidate(teacherAssignmentsProvider),
                      child: ListView(
                        key: ValueKey(_bySubject),
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: BrutalButton(
                              expand: true,
                              onTap: () =>
                                  context.push('${Routes.assignments}/new'),
                              icon: Icons.add,
                              label: 'Nueva tarea o examen',
                            ),
                          ),
                          if (_bySubject)
                            ..._subjectCards(context, subjects, mine)
                          else
                            ..._generalList(context, mine),
                        ],
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

  List<Widget> _subjectCards(
    BuildContext context,
    List<TeacherClass> subjects,
    List<Assignment> mine,
  ) {
    return [
      for (final (i, s) in subjects.indexed)
        entranceItem(
          context,
          i,
          _SubjectCard(
            subject: s,
            tasks:
                mine.where((a) => _sameSubject(a.subjectName, s.name)).toList(),
            onTap: () => context.push(
              '${Routes.assignments}/subject/${Uri.encodeComponent(s.name)}',
            ),
          ),
        ),
    ];
  }

  List<Widget> _generalList(BuildContext context, List<Assignment> mine) {
    return [
      for (final (i, a) in _byCreation(mine).indexed)
        entranceItem(context, i, _AssignmentTile(assignment: a)),
    ];
  }
}

/// Panel de una materia: tareas, pruebas, exámenes y trabajos en tarjetas.
class TeacherSubjectAssignmentsScreen extends ConsumerWidget {
  const TeacherSubjectAssignmentsScreen({super.key, required this.subject});

  final String subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(teacherAssignmentsProvider);
    return StudentDetailScaffold(
      title: subject,
      scrollable: false,
      bottomNav: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: list.when(
          loading: () => const SkeletonList(),
          error: (e, _) => ErrorStateView(message: '$e'),
          data: (all) {
            final items = _byCreation(
              all.where((a) => _sameSubject(a.subjectName, subject)),
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: BrutalButton(
                    expand: true,
                    onTap: () => context.push('${Routes.assignments}/new'),
                    icon: Icons.add,
                    label: 'Nueva tarea o examen',
                  ),
                ),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: Icons.assignment_rounded,
                      title: 'Sin tareas',
                      subtitle: 'Aún no hay tareas en esta materia.',
                    ),
                  )
                else
                  for (final (i, a) in items.indexed)
                    entranceItem(context, i, _AssignmentTile(assignment: a)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AssignmentTile extends StatelessWidget {
  const _AssignmentTile({required this.assignment});

  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AssignmentCard(
        assignment: assignment,
        pastel: true,
        onTap: () => context.push('${Routes.assignments}/${assignment.id}'),
      ),
    );
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
        margin: const EdgeInsets.only(right: 3, bottom: 3),
        decoration: Brutal.decoration(
          context,
          color: selected ? palette.accentDeep : palette.cardElevated,
          radius: Radii.md,
          offset: 3,
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

/// Tarjeta de materia: ícono, nombre y resumen de tareas.
class _SubjectCard extends StatelessWidget {
  const _SubjectCard({
    required this.subject,
    required this.tasks,
    required this.onTap,
  });

  final TeacherClass subject;
  final List<Assignment> tasks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subjectColor(subject.name));
    final ink = Brutal.ink(context);
    final summary = tasks.isEmpty
        ? 'Sin tareas'
        : '${tasks.length} elemento${tasks.length == 1 ? '' : 's'}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BrutalBox(
        onTap: onTap,
        color: s.surface,
        radius: Radii.lg,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: s.vivid,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: ink, width: Brutal.border),
              ),
              child: Icon(subject.icon, color: Colors.white, size: 24),
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
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: ink, width: Brutal.border),
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
    );
  }
}
