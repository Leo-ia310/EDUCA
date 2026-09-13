import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../../shared/models/app_role.dart';
import '../../domain/entities.dart';
import '../controllers/assignment_detail_controller.dart';
import '../controllers/submission_controller.dart';
import '../widgets/attachment_pill.dart';

/// Vista común para la tarea. Cambia layout según rol:
/// - Docente: ve descripción + atajo a calificar entregas.
/// - Estudiante: ve descripción + form de entrega + su nota si ya está.
/// - Padre: ve descripción + estado de entrega de su hijo (read-only).
class AssignmentDetailScreen extends ConsumerWidget {
  const AssignmentDetailScreen({
    super.key,
    required this.assignmentId,
    this.studentId,
  });

  final String assignmentId;
  final int? studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentAsync = ref.watch(assignmentByIdProvider(assignmentId));
    final user = ref.watch(authControllerProvider).user;
    final role = user?.activeRole ?? AppRole.student;

    return AppScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Atrás',
          onPressed: () => context.pop(),
        ),
        title: const Text('Detalle de tarea'),
        actions: [
          if (role == AppRole.teacher)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar',
              onPressed: () => context.push(
                '${Routes.assignments}/$assignmentId/edit',
              ),
            ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: assignmentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (a) {
          if (a == null) {
            return const EmptyState(
                icon: Icons.error_outline, title: 'No encontrada');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(assignment: a),
              const SizedBox(height: 16),
              if (a.description != null && a.description!.isNotEmpty) ...[
                const SectionHeader(title: 'Descripción'),
                const SizedBox(height: 8),
                EduCard(
                  child: Text(a.description!,
                      style: context.textTheme.bodyMedium),
                ),
                const SizedBox(height: 16),
              ],
              if (a.instructions != null && a.instructions!.isNotEmpty) ...[
                const SectionHeader(title: 'Instrucciones'),
                const SizedBox(height: 8),
                EduCard(
                  child: Text(a.instructions!,
                      style: context.textTheme.bodyMedium),
                ),
                const SizedBox(height: 16),
              ],
              if (a.attachments.isNotEmpty) ...[
                const SectionHeader(title: 'Archivos adjuntos'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final at in a.attachments) AttachmentPill(attachment: at),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (role == AppRole.teacher)
                _TeacherActions(assignment: a)
              else
                _StudentBlock(assignment: a, studentId: studentId ?? 1001),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.assignment});
  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subjectColor(assignment.subjectName));
    final deep = Color.lerp(s.vivid, Colors.black, 0.18)!;
    final fmt = DateFormat("EEE d MMM, HH:mm", 'es');
    final statusLabel = switch (assignment.statusForNow(DateTime.now())) {
      AssignmentStatus.draft => 'Borrador',
      AssignmentStatus.open => 'Abierta',
      AssignmentStatus.dueSoon => 'Vence pronto',
      AssignmentStatus.overdue => 'Vencida',
      AssignmentStatus.closed => 'Cerrada',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [s.vivid, deep],
        ),
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HeroChip(label: assignment.kind.label),
              const SizedBox(width: 8),
              _HeroChip(label: statusLabel),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            assignment.title,
            style: context.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${assignment.subjectName} · ${assignment.groupName}',
            style: context.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.event, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                'Entrega ${fmt.format(assignment.dueAt)}',
                style: context.textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _HeroChip(label: '${assignment.maxScore.toStringAsFixed(0)} pts'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chip translúcido blanco para los heros del panel.
class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TeacherActions extends StatelessWidget {
  const _TeacherActions({required this.assignment});
  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Entregas'),
        const SizedBox(height: 8),
        EduCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${assignment.submittedCount} / ${assignment.totalStudents} entregadas',
                          style: context.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${assignment.gradedCount} calificadas',
                          style: context.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => context.push(
                      '${Routes.assignments}/${assignment.id}/grade',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Calificar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StudentBlock extends ConsumerStatefulWidget {
  const _StudentBlock({required this.assignment, required this.studentId});
  final Assignment assignment;
  final int studentId;

  @override
  ConsumerState<_StudentBlock> createState() => _StudentBlockState();
}

class _StudentBlockState extends ConsumerState<_StudentBlock> {
  bool _hydrated = false;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    final files = <File>[];
    for (final f in result.files) {
      if (f.path != null) files.add(File(f.path!));
    }
    await ref.read(submissionControllerProvider.notifier).addFiles(files);
  }

  @override
  Widget build(BuildContext context) {
    final args = (
      assignmentId: widget.assignment.id,
      studentId: widget.studentId
    );
    final mine = ref.watch(mySubmissionProvider(args));
    final state = ref.watch(submissionControllerProvider);
    final controller = ref.read(submissionControllerProvider.notifier);
    final palette = context.palette;

    // Hidratar el form la primera vez (con cualquier entrega previa).
    if (!_hydrated && mine.hasValue) {
      _hydrated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.hydrate(
          assignmentId: widget.assignment.id,
          studentId: widget.studentId,
          existing: mine.value,
        );
        _notesCtrl.text = mine.value?.studentNotes ?? '';
      });
    }

    final user = ref.read(authControllerProvider).user;
    final isParent = user?.activeRole == AppRole.parent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Mi entrega'),
        const SizedBox(height: 8),
        mine.when(
          loading: () => const EduCard(
              child: Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )),
          error: (e, _) => EduCard(child: Text('$e')),
          data: (existing) {
            if (existing?.status == SubmissionStatus.graded) {
              return _GradedView(submission: existing!, assignment: widget.assignment);
            }
            if (isParent) {
              return EduCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null
                          ? 'Aún no entregada'
                          : 'Entregada — esperando calificación',
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (existing?.attachments.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final a in existing!.attachments)
                            AttachmentPill(attachment: a),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }
            return EduCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (existing != null) ...[
                    Text(
                      'Ya entregaste el ${DateFormat("d MMM HH:mm", 'es').format(existing.submittedAt!)}',
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: palette.success),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: _notesCtrl,
                    minLines: 2,
                    maxLines: 5,
                    onChanged: controller.setNotes,
                    decoration: const InputDecoration(
                      labelText: 'Comentario (opcional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (state.attachments.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final a in state.attachments)
                          AttachmentPill(
                            attachment: a,
                            onRemove: () => controller.removeAttachment(a.id),
                          ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: state.uploading ? null : _pickFiles,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        icon: state.uploading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.upload_file_rounded),
                        label: Text(
                            state.uploading ? 'Subiendo…' : 'Adjuntar'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: state.saving
                            ? null
                            : () async {
                                final result =
                                    await controller.submit();
                                if (result != null && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        result.isLate
                                            ? 'Entregado tarde'
                                            : '¡Entrega enviada!',
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.send_rounded),
                        label: Text(state.saving
                            ? 'Enviando…'
                            : (existing == null
                                ? 'Enviar entrega'
                                : 'Reemplazar entrega')),
                      ),
                    ],
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: 8),
                    Text(state.error!,
                        style: TextStyle(color: palette.danger)),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _GradedView extends StatelessWidget {
  const _GradedView({required this.submission, required this.assignment});
  final Submission submission;
  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2FA869), Color(0xFF35C97E), Color(0xFF2FB39A)],
        ),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: Colors.white, size: 28),
              const SizedBox(width: 8),
              Text(
                'Calificada',
                style: context.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${submission.score!.toStringAsFixed(1)} / ${assignment.maxScore.toStringAsFixed(0)}',
                style: context.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (submission.feedback != null) ...[
            const SizedBox(height: 10),
            Text(
              'Comentario del maestro',
              style: context.textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              submission.feedback!,
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: Colors.white),
            ),
          ],
          if (submission.attachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in submission.attachments) AttachmentPill(attachment: a),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
