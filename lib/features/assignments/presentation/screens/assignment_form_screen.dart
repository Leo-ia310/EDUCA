import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../attendance/data/mock_attendance_data.dart';
import '../../domain/entities.dart';
import '../../providers.dart';
import '../controllers/assignment_detail_controller.dart';
import '../controllers/assignment_form_controller.dart';
import '../controllers/assignments_list_controller.dart';
import '../widgets/attachment_pill.dart';

class AssignmentFormScreen extends ConsumerStatefulWidget {
  const AssignmentFormScreen({
    super.key,
    this.assignmentId,
    this.classId,
  });

  /// Si viene, edita; si no, crea.
  final String? assignmentId;
  final int? classId;

  @override
  ConsumerState<AssignmentFormScreen> createState() =>
      _AssignmentFormScreenState();
}

class _AssignmentFormScreenState extends ConsumerState<AssignmentFormScreen> {
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_hydrated) return;
      _hydrated = true;
      final controller =
          ref.read(assignmentFormControllerProvider.notifier);
      if (widget.assignmentId != null) {
        final a = await ref
            .read(assignmentRepositoryProvider)
            .assignmentById(widget.assignmentId!);
        if (a != null) controller.hydrate(a);
      } else if (widget.classId != null) {
        controller.setClass(widget.classId!);
      }
    });
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    final files = <File>[];
    for (final f in result.files) {
      if (f.path != null) files.add(File(f.path!));
    }
    await ref
        .read(assignmentFormControllerProvider.notifier)
        .addFiles(files);
  }

  Future<void> _pickDate(BuildContext context, DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    ref.read(assignmentFormControllerProvider.notifier).setDueAt(
          DateTime(picked.year, picked.month, picked.day, time.hour,
              time.minute),
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assignmentFormControllerProvider);
    final controller = ref.read(assignmentFormControllerProvider.notifier);
    final palette = context.palette;
    final fmt = DateFormat("d MMM y, HH:mm", 'es');

    return AppScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(state.assignmentId == null ? 'Nueva tarea' : 'Editar tarea'),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Información'),
          const SizedBox(height: 8),
          EduCard(
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: 'Título'),
                  controller: TextEditingController(text: state.title)
                    ..selection = TextSelection.fromPosition(
                        TextPosition(offset: state.title.length)),
                  onChanged: controller.setTitle,
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration:
                      const InputDecoration(labelText: 'Descripción'),
                  minLines: 2,
                  maxLines: 4,
                  controller: TextEditingController(text: state.description)
                    ..selection = TextSelection.fromPosition(
                        TextPosition(offset: state.description.length)),
                  onChanged: controller.setDescription,
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration:
                      const InputDecoration(labelText: 'Instrucciones'),
                  minLines: 2,
                  maxLines: 6,
                  controller: TextEditingController(text: state.instructions)
                    ..selection = TextSelection.fromPosition(
                        TextPosition(offset: state.instructions.length)),
                  onChanged: controller.setInstructions,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const SectionHeader(title: 'Configuración'),
          const SizedBox(height: 8),
          EduCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: state.classId,
                        decoration:
                            const InputDecoration(labelText: 'Clase'),
                        items: [
                          for (final c in AttendanceMock.todaysClasses)
                            DropdownMenuItem(
                              value: c.classId,
                              child: Text('${c.subjectName} · ${c.groupName}',
                                  overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) controller.setClass(v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<AssignmentKind>(
                        value: state.kind,
                        decoration:
                            const InputDecoration(labelText: 'Tipo'),
                        items: [
                          for (final k in AssignmentKind.values)
                            DropdownMenuItem(value: k, child: Text(k.label)),
                        ],
                        onChanged: (v) {
                          if (v != null) controller.setKind(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        decoration:
                            const InputDecoration(labelText: 'Puntaje máximo'),
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(
                            text: state.maxScore.toStringAsFixed(0)),
                        onChanged: (v) {
                          final n = double.tryParse(v);
                          if (n != null && n > 0) controller.setMaxScore(n);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.calendar_today_rounded,
                      color: palette.limeDeep),
                  title: const Text('Fecha de entrega'),
                  subtitle: Text(fmt.format(state.dueAt)),
                  onTap: () => _pickDate(context, state.dueAt),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Permitir entrega tardía'),
                  value: state.allowLate,
                  activeColor: palette.limeDeep,
                  onChanged: controller.setAllowLate,
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Publicar inmediatamente'),
                  subtitle:
                      const Text('Si lo apagas, queda como borrador.'),
                  value: state.published,
                  activeColor: palette.limeDeep,
                  onChanged: controller.setPublished,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const SectionHeader(title: 'Archivos'),
          const SizedBox(height: 8),
          EduCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.attachments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Aún no has adjuntado archivos.',
                      style: context.textTheme.bodySmall,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in state.attachments)
                        AttachmentPill(
                          attachment: a,
                          onRemove: () => controller.removeAttachment(a.id),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: state.uploading ? null : _pickFiles,
                      icon: state.uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_rounded),
                      label: Text(state.uploading ? 'Subiendo…' : 'Adjuntar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (state.error != null) ...[
            Text(
              state.error!,
              style: TextStyle(color: palette.danger),
            ),
            const SizedBox(height: 12),
          ],

          FilledButton.icon(
            onPressed: state.saving
                ? null
                : () async {
                    final result = await ref
                        .read(assignmentFormControllerProvider.notifier)
                        .save();
                    if (result == null || !context.mounted) return;
                    ref.invalidate(teacherAssignmentsProvider);
                    context.pop();
                  },
            icon: const Icon(Icons.check_rounded),
            label: Text(state.saving
                ? 'Guardando…'
                : (state.assignmentId == null
                    ? 'Crear tarea'
                    : 'Guardar cambios')),
          ),
        ],
      ),
    );
  }
}
