import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../domain/entities.dart';
import 'assignment_status_chip.dart';

/// Tarjeta de tarea reutilizable en lista docente y feed estudiante.
class AssignmentCard extends StatelessWidget {
  const AssignmentCard({
    super.key,
    required this.assignment,
    this.onTap,
    this.showProgress = true,
    this.studentStatus,
    this.studentScore,
    this.pastel = false,
  });

  final Assignment assignment;
  final VoidCallback? onTap;

  /// Si se muestra (rol docente) la barra de progreso de entregas+calificación.
  final bool showProgress;

  /// Si se trata de la vista estudiante, mostramos el chip de SU estado.
  final SubmissionStatus? studentStatus;
  final double? studentScore;

  /// Estilo pastel (feed del alumno): fondo tintado por materia + ícono en
  /// círculo vívido, igual que las tarjetas de materia. El docente usa el
  /// estilo clásico (pastel = false).
  final bool pastel;

  static const _ink = Color(0xFF232A33);

  static IconData _kindIcon(AssignmentKind kind) => switch (kind) {
        AssignmentKind.homework => Icons.assignment_rounded,
        AssignmentKind.exam => Icons.school_rounded,
        AssignmentKind.project => Icons.workspaces_rounded,
        AssignmentKind.quiz => Icons.quiz_rounded,
        AssignmentKind.presentation => Icons.slideshow_rounded,
      };

  @override
  Widget build(BuildContext context) {
    if (pastel) return _buildPastel(context);
    return _buildClassic(context);
  }

  Widget _buildPastel(BuildContext context) {
    final base = subjectColor(assignment.subjectName);
    final hsl = HSLColor.fromColor(base);
    final vivid = hsl
        .withSaturation(hsl.saturation.clamp(0.5, 1.0))
        .withLightness(0.56)
        .toColor();
    final cardBg = hsl
        .withSaturation(hsl.saturation.clamp(0.35, 1.0))
        .withLightness(0.94)
        .toColor();
    final inkMuted = _ink.withValues(alpha: 0.62);
    final status = assignment.statusForNow(DateTime.now());
    final fmt = DateFormat("d MMM, HH:mm", 'es');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ícono en círculo vívido según el tipo de tarea.
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: vivid,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _kindIcon(assignment.kind),
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AssignmentStatusChip(status: status),
                          const Spacer(),
                          if (studentStatus != null)
                            SubmissionStatusChip(status: studentStatus!),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        assignment.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleMedium?.copyWith(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${assignment.subjectName} · ${assignment.groupName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: inkMuted),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 14, color: inkMuted),
                          const SizedBox(width: 4),
                          Text(
                            'Entrega ${fmt.format(assignment.dueAt)}',
                            style: context.textTheme.labelSmall
                                ?.copyWith(color: inkMuted),
                          ),
                          const Spacer(),
                          if (studentScore != null)
                            Text(
                              '${studentScore!.toStringAsFixed(1)} / ${assignment.maxScore.toStringAsFixed(0)}',
                              style: context.textTheme.titleSmall?.copyWith(
                                color: const Color(0xFF2E7D46),
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          else
                            Text(
                              '${assignment.maxScore.toStringAsFixed(0)} pts',
                              style: context.textTheme.labelSmall
                                  ?.copyWith(color: inkMuted),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClassic(BuildContext context) {
    final palette = context.palette;
    final status = assignment.statusForNow(DateTime.now());
    final fmt = DateFormat("d MMM, HH:mm", 'es');
    return EduCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.limeSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  assignment.kind.label,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: palette.limeDeep,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AssignmentStatusChip(status: status),
              const Spacer(),
              if (studentStatus != null) ...[
                SubmissionStatusChip(status: studentStatus!),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            assignment.title,
            style: context.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${assignment.subjectName} · ${assignment.groupName}',
            style: context.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 14, color: palette.textMuted),
              const SizedBox(width: 4),
              Text(
                'Entrega ${fmt.format(assignment.dueAt)}',
                style: context.textTheme.labelSmall
                    ?.copyWith(color: palette.textMuted),
              ),
              const Spacer(),
              if (studentScore != null) ...[
                Text(
                  '${studentScore!.toStringAsFixed(1)} / ${assignment.maxScore.toStringAsFixed(0)}',
                  style: context.textTheme.titleSmall?.copyWith(
                    color: palette.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ] else
                Text(
                  '${assignment.maxScore.toStringAsFixed(0)} pts',
                  style: context.textTheme.labelSmall
                      ?.copyWith(color: palette.textMuted),
                ),
            ],
          ),
          if (showProgress && assignment.totalStudents > 0) ...[
            const SizedBox(height: 12),
            _ProgressBlock(assignment: assignment),
          ],
          if (assignment.attachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.attach_file_rounded,
                    size: 14, color: palette.textMuted),
                const SizedBox(width: 4),
                Text(
                  '${assignment.attachments.length} archivo${assignment.attachments.length == 1 ? '' : 's'}',
                  style: context.textTheme.labelSmall
                      ?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.assignment});
  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _ProgressBar(
                progress: assignment.submissionProgress,
                label: 'Entregadas',
                count:
                    '${assignment.submittedCount}/${assignment.totalStudents}',
                color: palette.info,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProgressBar(
                progress: assignment.gradingProgress,
                label: 'Calificadas',
                count:
                    '${assignment.gradedCount}/${assignment.submittedCount}',
                color: palette.success,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.progress,
    required this.label,
    required this.count,
    required this.color,
  });
  final double progress;
  final String label;
  final String count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: context.textTheme.labelSmall),
            ),
            Text(count,
                style: context.textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w800, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
