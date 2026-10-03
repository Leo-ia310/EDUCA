import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/entrance.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../domain/entities.dart';
import '../controllers/assignment_detail_controller.dart';
import '../controllers/assignments_list_controller.dart';
import '../widgets/assignment_card.dart';

/// Feed de tareas para estudiante y padre. El `studentId` es el del
/// estudiante observado (en padre, el hijo seleccionado; en estudiante, él
/// mismo).
class StudentAssignmentsScreen extends ConsumerWidget {
  const StudentAssignmentsScreen({super.key, required this.studentId});
  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(studentAssignmentsProvider);
    final palette = context.palette;

    return StudentDetailScaffold(
      title: 'Mis tareas',
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: crossfadeState(
          context,
          list.when(
          loading: () => const SkeletonList(),
          error: (e, _) => ErrorStateView(message: '$e'),
          data: (allItems) {
            // Solo tareas: los exámenes/quizzes viven en "Mis pruebas".
            final items = allItems
                .where((a) =>
                    a.kind != AssignmentKind.exam &&
                    a.kind != AssignmentKind.quiz,)
                .toList();
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.task_alt_rounded,
                title: 'Todo al día',
                subtitle: 'No tienes tareas asignadas en este momento.',
                actionLabel: 'Ver horario',
                onAction: () => context.go(Routes.schedule),
              );
            }
            // Pendientes: sin entrega; Entregadas: con entrega registrada.
            bool delivered(Assignment a) {
              final st = ref
                  .watch(
                    mySubmissionProvider(
                      (assignmentId: a.id, studentId: studentId),
                    ),
                  )
                  .asData
                  ?.value
                  ?.status;
              return st != null && st != SubmissionStatus.pending;
            }

            final pending = items.where((a) => !delivered(a)).toList();
            final done = items.where(delivered).toList();
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
                          onTap: () =>
                              context.push('${Routes.assignments}/${a.id}'),
                        ),
                      ),
                  ],
                );

            return RefreshIndicator(
              color: palette.accentDeep,
              onRefresh: () async =>
                  ref.invalidate(studentAssignmentsProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
                children: [
                  if (pending.isNotEmpty) ...[
                    section('Pendientes', pending),
                    const SizedBox(height: 16),
                  ],
                  if (done.isNotEmpty) section('Entregadas', done),
                ],
              ),
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
