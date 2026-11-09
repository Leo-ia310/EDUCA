import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../domain/entities.dart';
import '../controllers/assignment_detail_controller.dart';
import '../widgets/assignment_status_chip.dart';
import '../widgets/submission_review_card.dart';

class GradingScreen extends ConsumerWidget {
  const GradingScreen({super.key, required this.assignmentId});
  final String assignmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentAsync = ref.watch(assignmentByIdProvider(assignmentId));
    final submissionsAsync =
        ref.watch(submissionsForAssignmentProvider(assignmentId));

    return StudentDetailScaffold(
      title: assignmentAsync.maybeWhen(
        data: (a) => a?.title ?? 'Calificar',
        orElse: () => 'Calificar',
      ),
      scrollable: false,
      bottomNav: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: assignmentAsync.when(
          loading: () => const SkeletonList(),
          error: (e, _) => Center(child: Text('$e')),
          data: (a) {
            if (a == null) {
              return const EmptyState(
                icon: Icons.error_outline,
                title: 'No encontrada',
              );
            }
            return submissionsAsync.when(
              loading: () => const SkeletonList(),
              error: (e, _) => Center(child: Text('$e')),
              data: (subs) =>
                  _SubmissionsList(assignment: a, submissions: subs),
            );
          },
        ),
      ),
    );
  }
}

class _SubmissionsList extends StatelessWidget {
  const _SubmissionsList({required this.assignment, required this.submissions});
  final Assignment assignment;
  final List<Submission> submissions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: DepthCard(
            padding: const EdgeInsets.all(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [palette.accent, palette.accentDeep],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${assignment.subjectName} · ${assignment.groupName}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AssignmentStatusChip(
                        status: assignment.statusForNow(DateTime.now()),
                      ),
                    ],
                  ),
                ),
                _CounterPill(
                  label: 'Entregadas',
                  value:
                      '${assignment.submittedCount}/${assignment.totalStudents}',
                ),
                const SizedBox(width: 8),
                _CounterPill(
                  label: 'Calificadas',
                  value:
                      '${assignment.gradedCount}/${assignment.submittedCount}',
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            itemCount: submissions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => SubmissionReviewCard(
              assignment: assignment,
              submission: submissions[i],
            ),
          ),
        ),
      ],
    );
  }
}

class _CounterPill extends StatelessWidget {
  const _CounterPill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: context.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800, color: Colors.white),
          ),
          Text(
            label,
            style: context.textTheme.labelSmall
                ?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }
}
