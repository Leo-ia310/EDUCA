import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../shared/models/app_role.dart';
import '../../data/admin_backend_repository.dart';
import '../../data/school_directory.dart';
import 'admin_widgets.dart';

/// Alta/edición de una clase: materia, salón, maestro y aula. Editar el
/// maestro o el salón de una clase existente es la "edición de asignación".
Future<void> showClassSheet(
  BuildContext context, {
  SchoolClass? existing,
  String? groupId,
}) {
  return showBrutalSheet<void>(
    context,
    title: existing == null ? 'Nueva clase' : 'Editar clase',
    child: _ClassForm(existing: existing, groupId: groupId),
  );
}

class _ClassForm extends ConsumerStatefulWidget {
  const _ClassForm({this.existing, this.groupId});
  final SchoolClass? existing;
  final String? groupId;

  @override
  ConsumerState<_ClassForm> createState() => _ClassFormState();
}

class _ClassFormState extends ConsumerState<_ClassForm> {
  late final TextEditingController _subject;
  late final TextEditingController _room;
  String? _groupId;
  String? _teacherId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _subject = TextEditingController(text: c?.subject ?? '');
    _room = TextEditingController(text: c?.room ?? '');
    _groupId = c?.groupId ?? widget.groupId;
    _teacherId = c?.teacherId;
  }

  @override
  void dispose() {
    _subject.dispose();
    _room.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final subject = _subject.text.trim();
    if (subject.isEmpty || _groupId == null) {
      setState(
        () => _error =
            subject.isEmpty ? 'La materia es obligatoria' : 'Elige un salón',
      );
      return;
    }
    final repo = ref.read(adminBackendRepositoryProvider);
    if (repo != null) {
      setState(() => _saving = true);
      try {
        final payload = <String, dynamic>{
          'subject': subject,
          'groupId': _groupId,
          'teacherId': _teacherId,
          'room': _room.text.trim(),
        };
        if (widget.existing == null) {
          await repo.createClass(payload);
        } else {
          await repo.updateClass(widget.existing!.id, payload);
        }
        ref.invalidate(adminSchoolDirectoryProvider);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = '$e'.replaceFirst('Bad state: ', '');
            _saving = false;
          });
        }
      }
      return;
    }
    final store = ref.read(schoolDirectoryProvider.notifier);
    final old = widget.existing;
    if (old == null) {
      store.addClass(
        SchoolClass(
          id: '',
          subject: subject,
          groupId: _groupId!,
          teacherId: _teacherId,
          room: _room.text.trim(),
        ),
      );
    } else {
      store.updateClass(
        SchoolClass(
          id: old.id,
          subject: subject,
          groupId: _groupId!,
          teacherId: _teacherId,
          room: _room.text.trim(),
        ),
      );
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final c = widget.existing!;
    if (!await confirmDelete(context, 'la clase ${c.subject}')) return;
    final repo = ref.read(adminBackendRepositoryProvider);
    if (repo != null) {
      await repo.archiveClass(c.id);
      ref.invalidate(adminSchoolDirectoryProvider);
    } else {
      ref.read(schoolDirectoryProvider.notifier).removeClass(c.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminBackendRepositoryProvider);
    final remote =
        repo == null ? null : ref.watch(adminSchoolDirectoryProvider);
    final SchoolDirectory dir =
        remote?.asData?.value ?? ref.watch(schoolDirectoryProvider);
    final teachers = dir.byRole(AppRole.teacher);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrutalTextField(
          controller: _subject,
          label: 'Materia',
          icon: Icons.menu_book_rounded,
          errorText:
              _error != null && _subject.text.trim().isEmpty ? _error : null,
        ),
        const SizedBox(height: 12),
        BrutalTextField(
          controller: _room,
          label: 'Aula',
          icon: Icons.meeting_room_rounded,
        ),
        const FormLabel('Salón / año'),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final g in dir.groups)
              BrutalPill(
                compact: true,
                label: g.name,
                selected: _groupId == g.id,
                onTap: () => setState(() => _groupId = g.id),
              ),
          ],
        ),
        if (_error != null && _groupId == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.palette.danger),
            ),
          ),
        const FormLabel('Maestro'),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            BrutalPill(
              compact: true,
              label: 'Sin asignar',
              selected: _teacherId == null,
              onTap: () => setState(() => _teacherId = null),
            ),
            for (final t in teachers)
              BrutalPill(
                compact: true,
                label: t.name,
                selected: _teacherId == t.id,
                onTap: () => setState(() => _teacherId = t.id),
              ),
          ],
        ),
        const SizedBox(height: 20),
        BrutalButton(
          expand: true,
          onTap: _saving ? () {} : () => _save(),
          icon: _saving ? Icons.hourglass_top_rounded : Icons.save_rounded,
          label: _saving
              ? 'Guardando…'
              : widget.existing == null
                  ? 'Crear'
                  : 'Guardar cambios',
        ),
        if (widget.existing != null) ...[
          const SizedBox(height: 10),
          BrutalButton(
            expand: true,
            onTap: _delete,
            icon: Icons.delete_outline_rounded,
            label: 'Eliminar',
            color: context.palette.danger,
          ),
        ],
      ],
    );
  }
}
