import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/entities.dart';
import '../controllers/assignment_detail_controller.dart';
import '../controllers/grading_controller.dart';
import '../widgets/assignment_status_chip.dart';
import '../widgets/attachment_pill.dart';

class GradingScreen extends ConsumerWidget {
  const GradingScreen({super.key, required this.assignmentId});
  final String assignmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentAsync = ref.watch(assignmentByIdProvider(assignmentId));
    final submissionsAsync =
        ref.watch(submissionsForAssignmentProvider(assignmentId));

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: assignmentAsync.maybeWhen(
          data: (a) => Text(a?.title ?? 'Tarea'),
          orElse: () => const Text('Tarea'),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: assignmentAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (a) {
            if (a == null) {
              return const EmptyState(
                  icon: Icons.error_outline, title: 'No encontrada');
            }
            return submissionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (subs) => _SubmissionsList(assignment: a, submissions: subs),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: EduCard(
            color: palette.lime,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${assignment.subjectName} · ${assignment.groupName}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF34401C),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AssignmentStatusChip(
                          status: assignment.statusForNow(DateTime.now())),
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
            itemBuilder: (_, i) => _SubmissionRow(
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
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value,
              style: context.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF1E2218))),
          Text(label,
              style: context.textTheme.labelSmall
                  ?.copyWith(color: const Color(0xFF34401C))),
        ],
      ),
    );
  }
}

class _SubmissionRow extends ConsumerWidget {
  const _SubmissionRow({required this.assignment, required this.submission});
  final Assignment assignment;
  final Submission submission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final fmt = DateFormat("d MMM, HH:mm", 'es');
    return EduCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: submission.studentName, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      submission.studentName,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (submission.submittedAt != null)
                      Text(
                        'Entregada ${fmt.format(submission.submittedAt!)}',
                        style: context.textTheme.bodySmall,
                      )
                    else
                      Text('Sin entregar',
                          style: context.textTheme.bodySmall),
                  ],
                ),
              ),
              SubmissionStatusChip(status: submission.status),
            ],
          ),
          if (submission.attachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in submission.attachments)
                  AttachmentPill(attachment: a),
              ],
            ),
          ],
          if (submission.score != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.star_rounded, size: 18, color: palette.success),
                const SizedBox(width: 4),
                Text(
                  '${submission.score!.toStringAsFixed(1)} / ${assignment.maxScore.toStringAsFixed(0)}',
                  style: context.textTheme.titleSmall?.copyWith(
                    color: palette.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (submission.feedback != null)
                  Expanded(
                    child: Text(
                      submission.feedback!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: context.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (submission.status == SubmissionStatus.pending)
                Text(
                  'Esperando entrega',
                  style: context.textTheme.labelSmall
                      ?.copyWith(color: palette.textMuted),
                )
              else
                FilledButton.tonal(
                  onPressed: () => _openGradeSheet(context, ref),
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.limeDeep,
                    foregroundColor: const Color(0xFF1E2218),
                    minimumSize: const Size(0, 38),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  ),
                  child: Text(submission.hasGrade
                      ? 'Ajustar nota'
                      : 'Calificar'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _openGradeSheet(BuildContext context, WidgetRef ref) {
    final scoreCtrl = TextEditingController(
        text: submission.score?.toStringAsFixed(1) ?? '');
    final feedbackCtrl =
        TextEditingController(text: submission.feedback ?? '');
    final palette = context.palette;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
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
        child: StatefulBuilder(
          builder: (ctx, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.textMuted.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Calificar a ${submission.studentName}',
                  style: context.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: scoreCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: InputDecoration(
                    labelText:
                        'Puntaje (max ${assignment.maxScore.toStringAsFixed(0)})',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: feedbackCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Comentario (opcional)',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final score = double.tryParse(scoreCtrl.text);
                    if (score == null) return;
                    final clamped = score.clamp(0, assignment.maxScore);
                    await ref.read(gradingControllerProvider.notifier).grade(
                          assignmentId: assignment.id,
                          submissionId: submission.id,
                          score: clamped.toDouble(),
                          feedback: feedbackCtrl.text.trim().isEmpty
                              ? null
                              : feedbackCtrl.text.trim(),
                        );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Guardar nota'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
