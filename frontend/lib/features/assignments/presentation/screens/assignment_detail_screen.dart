import '../../../portal_access/providers.dart';
import '../../../portal_access/access_widgets.dart';
import '../../../collaborations/providers.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/celebration.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../../shared/models/app_role.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../../dashboard/providers.dart';
import '../../domain/entities.dart';
import '../../providers.dart';
import '../controllers/assignment_detail_controller.dart';
import '../controllers/assignments_list_controller.dart';
import '../controllers/originality_controller.dart';
import '../widgets/assignment_status_chip.dart';
import '../widgets/originality_summary_card.dart';
import '../widgets/submission_review_card.dart';
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

    final isTeacher = role == AppRole.teacher;
    final loaded = assignmentAsync.valueOrNull;
    final canEdit = isTeacher &&
        loaded != null &&
        ref.watch(
          classPermissionProvider((loaded.classId, 'assignments.create')),
        );

    return StudentDetailScaffold(
      title: 'Detalle de tarea',
      bottomNav: false,
      topActions: [
        if (canEdit)
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: Colors.white),
            tooltip: 'Editar',
            onPressed: () => context.push(
              '${Routes.assignments}/$assignmentId/edit',
            ),
          ),
      ],
      child: assignmentAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Center(child: Text('$e')),
        data: (a) {
          if (a == null) {
            return const EmptyState(
              icon: Icons.error_outline,
              title: 'No encontrada',
            );
          }
          final canSeeFiles =
              isTeacher || ref.watch(portalCanProvider('materials.view'));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(assignment: a, teacherView: isTeacher),
              const SizedBox(height: 16),
              if (isTeacher) ...[
                _TeacherOverview(assignment: a),
                const SizedBox(height: 16),
                _TeacherSettings(assignment: a),
                const SizedBox(height: 16),
                if (canEdit) ...[
                  _TeacherManageBar(assignment: a),
                  const SizedBox(height: 16),
                ],
              ],
              if (a.description != null && a.description!.isNotEmpty) ...[
                const SectionHeader(title: 'Descripción'),
                const SizedBox(height: 8),
                DepthCard(
                  brutal: true,
                  soft: true,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    a.description!,
                    style: context.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (a.instructions != null && a.instructions!.isNotEmpty) ...[
                const SectionHeader(title: 'Instrucciones'),
                const SizedBox(height: 8),
                DepthCard(
                  brutal: true,
                  soft: true,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    a.instructions!,
                    style: context.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (a.attachments.isNotEmpty && canSeeFiles) ...[
                SectionHeader(
                  title: 'Archivos adjuntos (${a.attachments.length})',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final at in a.attachments)
                      AttachmentPill(attachment: at),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (isTeacher) ...[
                if (ref.watch(
                  classPermissionProvider((a.classId, 'assignments.review')),
                )) ...[
                  OriginalitySummaryCard(
                    assignmentId: a.id,
                    canEditTemplate: canEdit,
                  ),
                  const SizedBox(height: 16),
                ],
                _SubmissionsSection(assignment: a),
              ] else
                _StudentBlock(assignment: a, studentId: studentId ?? 1001),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.assignment, this.teacherView = false});
  final Assignment assignment;
  final bool teacherView;

  static IconData _kindIcon(AssignmentKind kind) => switch (kind) {
        AssignmentKind.homework => Icons.assignment_rounded,
        AssignmentKind.exam => Icons.school_rounded,
        AssignmentKind.project => Icons.workspaces_rounded,
        AssignmentKind.quiz => Icons.quiz_rounded,
        AssignmentKind.presentation => Icons.slideshow_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subjectColor(assignment.subjectName));
    final fmt = DateFormat("EEE d MMM, HH:mm", 'es');
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(right: 4, bottom: 4),
      decoration: Brutal.decoration(
        context,
        color: s.vivid,
        radius: Radii.lg,
      ),
      child: Stack(
        children: [
          // Ícono grande de fondo (marca de agua) según el tipo de tarea.
          Positioned(
            right: -18,
            bottom: -18,
            child: Icon(
              _kindIcon(assignment.kind),
              size: 120,
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      assignment.dueAt == null
                          ? 'Sin fecha de entrega'
                          : 'Entrega ${fmt.format(assignment.dueAt!)}',
                      style: context.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _HeroChip(
                      label: '${assignment.maxScore.toStringAsFixed(0)} pts',
                    ),
                  ],
                ),
                if (teacherView) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      AssignmentStatusChip(
                        status: assignment.statusForNow(DateTime.now()),
                        onPastel: true,
                      ),
                      const SizedBox(width: 8),
                      _HeroChip(label: assignment.kind.label),
                    ],
                  ),
                ],
              ],
            ),
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

/// Resumen numérico de la tarea: entregadas, calificadas y por entregar.
class _TeacherOverview extends StatelessWidget {
  const _TeacherOverview({required this.assignment});
  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final a = assignment;
    final missing = (a.totalStudents - a.submittedCount).clamp(0, 1 << 30);
    final toGrade = (a.submittedCount - a.gradedCount).clamp(0, 1 << 30);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Resumen'),
        const SizedBox(height: 8),
        DepthCard(
          brutal: true,
          soft: true,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  _Stat(
                    value: '${a.submittedCount}/${a.totalStudents}',
                    label: 'Entregadas',
                    color: palette.accentDeep,
                  ),
                  _Stat(
                    value: '${a.gradedCount}',
                    label: 'Calificadas',
                    color: palette.success,
                  ),
                  _Stat(
                    value: '$toGrade',
                    label: 'Por calificar',
                    color: palette.warning,
                  ),
                  _Stat(
                    value: '$missing',
                    label: 'Sin entregar',
                    color: palette.danger,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ProgressLine(
                label: 'Entregas',
                value: a.submissionProgress,
                color: palette.accentDeep,
              ),
              const SizedBox(height: 8),
              _ProgressLine(
                label: 'Calificación',
                value: a.gradingProgress,
                color: palette.success,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: context.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: context.textTheme.labelSmall
                ?.copyWith(color: context.palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: context.textTheme.labelMedium
                ?.copyWith(color: palette.textMuted),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${(value * 100).round()} %',
            textAlign: TextAlign.end,
            style: context.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// Reglas con las que se configuró la tarea (visibles de un vistazo).
class _TeacherSettings extends StatelessWidget {
  const _TeacherSettings({required this.assignment});
  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final a = assignment;
    final fmt = DateFormat("d MMM y, HH:mm", 'es');
    Widget row(IconData icon, String title, String value, {bool? on}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 20, color: palette.accentDeep),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: context.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (on != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: (on ? palette.success : palette.textMuted)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  value,
                  style: context.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: on ? palette.success : palette.textMuted,
                  ),
                ),
              )
            else
              Text(
                value,
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: palette.textMuted),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Configuración'),
        const SizedBox(height: 8),
        DepthCard(
          brutal: true,
          soft: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              row(Icons.event_rounded, 'Asignada', fmt.format(a.assignedAt)),
              row(
                Icons.schedule_rounded,
                'Entrega tardía',
                a.allowLate ? 'Permitida' : 'No permitida',
                on: a.allowLate,
              ),
              row(
                Icons.chat_bubble_outline_rounded,
                'Comentarios del estudiante',
                a.allowStudentComments ? 'Activados' : 'Desactivados',
                on: a.allowStudentComments,
              ),
              row(
                Icons.visibility_rounded,
                'Visibilidad',
                a.published ? 'Publicada' : 'Borrador',
                on: a.published,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Acciones de gestión: editar, publicar/pasar a borrador y eliminar.
class _TeacherManageBar extends ConsumerStatefulWidget {
  const _TeacherManageBar({required this.assignment});
  final Assignment assignment;

  @override
  ConsumerState<_TeacherManageBar> createState() => _TeacherManageBarState();
}

class _TeacherManageBarState extends ConsumerState<_TeacherManageBar> {
  bool _busy = false;

  Future<void> _togglePublished() async {
    final a = widget.assignment;
    setState(() => _busy = true);
    try {
      await ref
          .read(assignmentRepositoryProvider)
          .publishAssignment(a.id, published: !a.published);
      ref.invalidate(assignmentByIdProvider(a.id));
      ref.invalidate(teacherAssignmentsProvider);
      ref.invalidate(teacherAssignmentCountsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo cambiar: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final a = widget.assignment;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: Text(
          '«${a.title}» dejará de verse para los estudiantes. '
          '¿Quieres eliminarla?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.danger,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(assignmentRepositoryProvider).deleteAssignment(a.id);
      ref.invalidate(teacherAssignmentsProvider);
      ref.invalidate(teacherAssignmentCountsProvider);
      ref.invalidate(teacherDashboardProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => context.push('${Routes.assignments}/${a.id}/edit'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Editar'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _togglePublished,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
            icon: Icon(
              a.published
                  ? Icons.visibility_off_rounded
                  : Icons.publish_rounded,
              size: 18,
            ),
            label: Text(a.published ? 'A borrador' : 'Publicar'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          onPressed: _busy ? null : _delete,
          tooltip: 'Eliminar',
          style: IconButton.styleFrom(
            minimumSize: const Size(46, 46),
            foregroundColor: palette.danger,
            side: BorderSide(color: palette.danger.withValues(alpha: 0.6)),
          ),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

enum _SubFilter {
  all('Todas'),
  delivered('Entregadas'),
  toGrade('Por calificar'),
  graded('Calificadas'),
  missing('Sin entregar');

  const _SubFilter(this.label);
  final String label;

  bool matches(Submission s) => switch (this) {
        _SubFilter.all => true,
        _SubFilter.delivered => s.status != SubmissionStatus.pending,
        _SubFilter.toGrade => s.status == SubmissionStatus.submitted ||
            s.status == SubmissionStatus.late,
        _SubFilter.graded => s.status == SubmissionStatus.graded,
        _SubFilter.missing => s.status == SubmissionStatus.pending,
      };
}

/// Entregas de los estudiantes con sus archivos y comentarios, filtrables.
class _SubmissionsSection extends ConsumerStatefulWidget {
  const _SubmissionsSection({required this.assignment});
  final Assignment assignment;

  @override
  ConsumerState<_SubmissionsSection> createState() =>
      _SubmissionsSectionState();
}

class _SubmissionsSectionState extends ConsumerState<_SubmissionsSection> {
  _SubFilter _filter = _SubFilter.all;
  bool _byOriginality = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    final canReview = ref.watch(
      classPermissionProvider((a.classId, 'assignments.review')),
    );
    if (!canReview) return const SizedBox.shrink();
    final palette = context.palette;
    final subs = ref.watch(submissionsForAssignmentProvider(a.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Entregas de los estudiantes'),
        const SizedBox(height: 8),
        subs.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => DepthCard(
            soft: true,
            padding: const EdgeInsets.all(16),
            child: Text('No se pudieron cargar las entregas.\n$e'),
          ),
          data: (list) {
            if (list.isEmpty) {
              return DepthCard(
                soft: true,
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Esta clase aún no tiene estudiantes matriculados.',
                  style: context.textTheme.bodyMedium
                      ?.copyWith(color: palette.textMuted),
                ),
              );
            }
            final summary =
                ref.watch(originalitySummaryProvider(a.id)).valueOrNull;
            final shown = [
              for (final s in list)
                if (_filter.matches(s)) s,
            ];
            if (_byOriginality && summary != null) {
              double cov(Submission s) =>
                  summary.itemFor(s.id)?.shownCoverage ?? -1;
              shown.sort((x, y) => cov(y).compareTo(cov(x)));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final f in _SubFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              '${f.label} · ${list.where(f.matches).length}',
                            ),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                        ),
                      if (summary != null && summary.withPercentage > 0) ...[
                        Container(
                          width: 1,
                          height: 22,
                          margin: const EdgeInsets.only(right: 8, top: 8),
                          color: palette.textMuted.withValues(alpha: 0.3),
                        ),
                        FilterChip(
                          avatar: const Icon(
                            Icons.sort_rounded,
                            size: 16,
                          ),
                          label: const Text('Ordenar por coincidencia'),
                          selected: _byOriginality,
                          onSelected: (v) => setState(() => _byOriginality = v),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'Ningún estudiante en «${_filter.label}».',
                        style: context.textTheme.bodyMedium
                            ?.copyWith(color: palette.textMuted),
                      ),
                    ),
                  )
                else
                  for (final s in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SubmissionReviewCard(assignment: a, submission: s),
                    ),
              ],
            );
          },
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
    final args =
        (assignmentId: widget.assignment.id, studentId: widget.studentId);
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
    final canSubmit = ref.watch(portalCanProvider('assignments.submit'));
    final gradesVisible =
        ref.watch(portalResolvedAccessProvider)?.annualGradesVisible ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Mi entrega'),
        const SizedBox(height: 8),
        mine.when(
          loading: () => const DepthCard(
            brutal: true,
            soft: true,
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => DepthCard(
            brutal: true,
            soft: true,
            padding: const EdgeInsets.all(16),
            child: Text('$e'),
          ),
          data: (existing) {
            if (existing?.status == SubmissionStatus.graded && !gradesVisible) {
              return const PortalRestriction(
                message: 'Las calificaciones están ocultas por tu institución.',
              );
            }
            if (existing?.status == SubmissionStatus.graded) {
              return _GradedView(
                submission: existing!,
                assignment: widget.assignment,
              );
            }
            if (isParent || !canSubmit) {
              return DepthCard(
                brutal: true,
                soft: true,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (existing == null ||
                              existing.status == SubmissionStatus.pending)
                          ? 'Aún no entregada'
                          : 'Entregada — esperando calificación',
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (existing?.attachments.isNotEmpty == true &&
                        ref.watch(portalCanProvider('materials.view'))) ...[
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
            return DepthCard(
              brutal: true,
              soft: true,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (existing?.submittedAt != null) ...[
                    Text(
                      'Ya entregaste el ${DateFormat("d MMM HH:mm", 'es').format(existing!.submittedAt!)}',
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: palette.success),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (widget.assignment.allowStudentComments) ...[
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
                  ],
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
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
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
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.upload_file_rounded),
                          label: Text(
                            state.uploading ? 'Subiendo…' : 'Adjuntar',
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                          ),
                          onPressed: state.saving
                              ? null
                              : () async {
                                  final result = await controller.submit();
                                  if (result != null && context.mounted) {
                                    showCelebration(
                                      context,
                                      icon: result.isLate
                                          ? Icons.schedule_rounded
                                          : Icons.check_circle_rounded,
                                      message: result.isLate
                                          ? 'Entregado tarde'
                                          : '¡Entrega enviada! 🎉',
                                    );
                                  }
                                },
                          icon: const Icon(Icons.send_rounded),
                          label: Text(
                            state.saving
                                ? 'Enviando…'
                                : (existing?.submittedAt == null
                                    ? 'Enviar entrega'
                                    : 'Reemplazar entrega'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      state.error!,
                      style: TextStyle(color: palette.danger),
                    ),
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

class _GradedView extends ConsumerWidget {
  const _GradedView({required this.submission, required this.assignment});
  final Submission submission;
  final Assignment assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              const Icon(
                Icons.workspace_premium_rounded,
                color: Colors.white,
                size: 28,
              ),
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
                '${submission.score?.toStringAsFixed(1) ?? '—'} / ${assignment.maxScore.toStringAsFixed(0)}',
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
              style:
                  context.textTheme.bodyMedium?.copyWith(color: Colors.white),
            ),
          ],
          if (submission.attachments.isNotEmpty &&
              ref.watch(portalCanProvider('materials.view'))) ...[
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
        ],
      ),
    );
  }
}
