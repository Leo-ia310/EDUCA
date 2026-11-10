import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../collaborations/providers.dart';
import '../../domain/entities.dart';
import '../controllers/grading_controller.dart';
import 'assignment_status_chip.dart';
import 'attachment_pill.dart';
import '../controllers/originality_controller.dart';
import 'originality_widgets.dart';

/// Tarjeta de una entrega para el docente: quién entregó, cuándo, el comentario
/// y los archivos del estudiante, la nota vigente y el acceso para calificar.
class SubmissionReviewCard extends ConsumerWidget {
  const SubmissionReviewCard({
    super.key,
    required this.assignment,
    required this.submission,
  });

  final Assignment assignment;
  final Submission submission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final fmt = DateFormat("d MMM, HH:mm", 'es');
    final delivered = submission.status != SubmissionStatus.pending;
    final notes = submission.studentNotes?.trim() ?? '';
    final canGrade = ref.watch(
      classPermissionProvider((assignment.classId, 'assignments.grade')),
    );

    return DepthCard(
      soft: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: submission.studentName, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      submission.studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      submission.submittedAt != null
                          ? 'Entregada ${fmt.format(submission.submittedAt!)}'
                          : 'Sin entregar',
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
              ),
              SubmissionStatusChip(status: submission.status),
            ],
          ),
          if (delivered && ref.watch(originalityApiProvider) != null) ...[
            const SizedBox(height: 12),
            OriginalityRow(
              assignmentId: assignment.id,
              submissionId: submission.id,
              item: ref.watch(
                originalitySummaryProvider(assignment.id).select(
                  (s) => s.valueOrNull?.itemFor(submission.id),
                ),
              ),
              loading: ref.watch(
                originalitySummaryProvider(assignment.id)
                    .select((s) => s.isLoading),
              ),
            ),
          ],
          if (delivered && submission.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Label(
              icon: Icons.attach_file_rounded,
              text:
                  'Archivos del estudiante (${submission.attachments.length})',
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in submission.attachments)
                  AttachmentPill(attachment: a),
              ],
            ),
          ] else if (delivered) ...[
            const SizedBox(height: 10),
            Text(
              'No adjuntó archivos.',
              style: context.textTheme.bodySmall
                  ?.copyWith(color: palette.textMuted),
            ),
          ],
          if (delivered && notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const _Label(
              icon: Icons.chat_bubble_outline_rounded,
              text: 'Comentario del estudiante',
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.accentSoft.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Text(notes, style: context.textTheme.bodyMedium),
            ),
          ],
          if (submission.score != null) ...[
            const SizedBox(height: 12),
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
              ],
            ),
            if (submission.feedback != null &&
                submission.feedback!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                submission.feedback!,
                style: context.textTheme.bodySmall
                    ?.copyWith(color: palette.textMuted),
              ),
            ],
          ],
          if (delivered && canGrade) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () => _openGradeSheet(context, ref),
                style: FilledButton.styleFrom(
                  backgroundColor: context.buttonFill,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 38),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                ),
                child: Text(
                  submission.hasGrade ? 'Ajustar nota' : 'Calificar',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openGradeSheet(BuildContext context, WidgetRef ref) {
    final scoreCtrl = TextEditingController(
      text: submission.score?.toStringAsFixed(1) ?? '',
    );
    final feedbackCtrl = TextEditingController(text: submission.feedback ?? '');
    final palette = context.palette;

    showModalBottomSheet<void>(
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
                decimal: true,
              ),
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
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Icon(icon, size: 15, color: palette.accentDeep),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: context.textTheme.labelMedium?.copyWith(
              color: palette.accentDeep,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
