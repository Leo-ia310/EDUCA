import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeleton.dart';
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

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Mis tareas'),
      ),
      bottomNav: const EducaBottomNav(),
      child: SafeArea(
        bottom: false,
        child: list.when(
          loading: () => const SkeletonList(),
          error: (e, _) => ErrorStateView(message: '$e'),
          data: (items) {
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.task_alt_outlined,
                title: 'Todo al día',
                subtitle: 'No tienes tareas asignadas en este momento.',
                actionLabel: 'Ver horario',
                onAction: () => context.go(Routes.schedule),
              );
            }
            final now = DateTime.now();
            final pending = items
                .where((a) =>
                    a.statusForNow(now) == AssignmentStatus.open ||
                    a.statusForNow(now) == AssignmentStatus.dueSoon)
                .toList();
            final past = items
                .where((a) =>
                    a.statusForNow(now) == AssignmentStatus.overdue ||
                    a.statusForNow(now) == AssignmentStatus.closed)
                .toList();
            return RefreshIndicator(
              color: palette.limeDeep,
              onRefresh: () async =>
                  ref.invalidate(studentAssignmentsProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (pending.isNotEmpty) ...[
                    const SectionHeader(title: 'Por entregar'),
                    const SizedBox(height: 8),
                    for (final a in pending)
                      _StudentTile(
                        assignment: a,
                        studentId: studentId,
                        onTap: () =>
                            context.push('${Routes.assignments}/${a.id}'),
                      ),
                  ],
                  if (past.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const SectionHeader(title: 'Pasadas'),
                    const SizedBox(height: 8),
                    for (final a in past)
                      _StudentTile(
                        assignment: a,
                        studentId: studentId,
                        onTap: () =>
                            context.push('${Routes.assignments}/${a.id}'),
                      ),
                  ],
                ],
              ),
            );
          },
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
        (assignmentId: assignment.id, studentId: studentId)));
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
              borderRadius: BorderRadius.circular(16),
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
