import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/admin_backend_repository.dart';
import '../../data/admin_schedule.dart';
import '../../data/demo_schedules.dart';
import '../../data/school_directory.dart';
import 'admin_widgets.dart';
import 'directory_picker.dart';

/// Alta/edición de un bloque de horario: clase (maestro y grupo salen de la
/// clase) o receso (de un grupo o de toda la institución).
Future<void> showScheduleSheet(
  BuildContext context, {
  AdminScheduleEntry? existing,
  String? groupId,
  int? weekdayId,
}) {
  return showBrutalSheet<void>(
    context,
    title: existing == null ? 'Nuevo horario' : 'Editar horario',
    child: _ScheduleForm(
      existing: existing,
      initialGroupId: groupId,
      initialWeekday: weekdayId,
    ),
  );
}

String _fmt(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay? _parse(String raw) {
  final parts = raw.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  return h == null || m == null ? null : TimeOfDay(hour: h, minute: m);
}

class _ScheduleForm extends ConsumerStatefulWidget {
  const _ScheduleForm({
    this.existing,
    this.initialGroupId,
    this.initialWeekday,
  });

  final AdminScheduleEntry? existing;
  final String? initialGroupId;
  final int? initialWeekday;

  @override
  ConsumerState<_ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends ConsumerState<_ScheduleForm> {
  late bool _isBreak;
  String? _classId;
  String? _groupId; // receso: null = toda la institución
  late final TextEditingController _label;
  late final TextEditingController _room;
  late Set<int> _days;
  TimeOfDay? _start;
  TimeOfDay? _end;
  String? _shift;
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _isBreak = e?.isBreak ?? false;
    _classId = e?.classId;
    _groupId = e?.isBreak ?? false ? e?.groupId : widget.initialGroupId;
    _label = TextEditingController(text: e?.isBreak ?? false ? e?.subject : '');
    _room = TextEditingController(text: e?.room ?? '');
    _days = {
      if (e != null)
        e.weekdayId
      else if (widget.initialWeekday != null)
        widget.initialWeekday!,
    };
    _start = e == null ? null : _parse(e.startTime);
    _end = e == null ? null : _parse(e.endTime);
    _shift = e?.shift;
  }

  @override
  void dispose() {
    _label.dispose();
    _room.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (start ? _start : _end) ??
          (start
              ? const TimeOfDay(hour: 8, minute: 0)
              : const TimeOfDay(hour: 9, minute: 0)),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => start ? _start = picked : _end = picked);
  }

  String? _validate() {
    if (!_isBreak && _classId == null) return 'Elige la clase';
    if (_isBreak && _label.text.trim().isEmpty) {
      return 'Escribe el nombre del receso';
    }
    if (_days.isEmpty) return 'Elige al menos un día';
    if (_start == null || _end == null) {
      return 'Indica la hora de inicio y la de fin';
    }
    final s = _start!.hour * 60 + _start!.minute;
    final e = _end!.hour * 60 + _end!.minute;
    if (e <= s) return 'La hora de fin debe ser posterior a la de inicio';
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final repo = ref.read(adminBackendRepositoryProvider);
    if (repo == null) {
      _saveDemo();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'kind': _isBreak ? 'break' : 'class',
        if (!_isBreak) 'classId': _classId,
        if (_isBreak) 'groupId': _groupId,
        if (_isBreak) 'label': _label.text.trim(),
        if (!_isBreak) 'room': _room.text.trim(),
        'startTime': _fmt(_start!),
        'endTime': _fmt(_end!),
        'shift': _shift,
      };
      if (_isNew) {
        final created = await repo.createSchedules({
          ...body,
          'weekdayIds': _days.toList()..sort(),
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              created.length == 1
                  ? 'Horario guardado correctamente'
                  : '${created.length} horarios guardados correctamente',
            ),
          ),
        );
      } else {
        await repo.updateSchedule(widget.existing!.id, {
          ...body,
          'weekdayId': _days.first,
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Cambios guardados')),
        );
      }
      ref.invalidate(adminSchedulesProvider);
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Sin servidor (demo): guarda en memoria con las mismas reglas de choque.
  void _saveDemo() {
    final SchoolDirectory dir = ref.read(schoolDirectoryProvider);
    final store = ref.read(demoSchedulesProvider.notifier);
    final cls = dir.classById(_classId);
    final room = _room.text.trim();
    final groupId = _isBreak ? _groupId : cls?.groupId;
    final teacherId = _isBreak ? null : cls?.teacherId;
    final days = _days.toList()..sort();

    for (final day in days) {
      final conflict = store.conflictFor(
        weekdayId: day,
        start: _fmt(_start!),
        end: _fmt(_end!),
        isBreak: _isBreak,
        groupId: groupId,
        teacherId: teacherId,
        room: _isBreak ? null : room,
        ignoreId: widget.existing?.id,
        dir: dir,
      );
      if (conflict != null) {
        setState(() => _error = conflict);
        return;
      }
    }

    final subject = _isBreak ? _label.text.trim() : (cls?.subject ?? '');
    final groupName = dir.group(groupId)?.name;
    final teacher = dir.person(teacherId)?.name;
    if (_isNew) {
      store.add(
        weekdayIds: days,
        isBreak: _isBreak,
        subject: subject,
        startTime: _fmt(_start!),
        endTime: _fmt(_end!),
        classId: _isBreak ? null : _classId,
        groupId: groupId,
        groupName: groupName,
        teacher: teacher,
        room: _isBreak || room.isEmpty ? null : room,
        shift: _shift,
      );
    } else {
      store.update(
        AdminScheduleEntry(
          id: widget.existing!.id,
          kind: _isBreak ? 'break' : 'class',
          weekdayId: days.first,
          startTime: _fmt(_start!),
          endTime: _fmt(_end!),
          subject: subject,
          classId: _isBreak ? null : _classId,
          groupId: groupId,
          groupName: groupName,
          teacher: teacher,
          room: _isBreak || room.isEmpty ? null : room,
          shift: _shift,
        ),
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isNew ? 'Horario guardado correctamente' : 'Cambios guardados',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final e = widget.existing!;
    if (!await confirmDelete(context, 'el horario de ${e.subject}')) return;
    if (!mounted) return;
    final repo = ref.read(adminBackendRepositoryProvider);
    if (repo == null) {
      ref.read(demoSchedulesProvider.notifier).remove(e.id);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horario eliminado')),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await repo.deleteSchedule(e.id);
      ref.invalidate(adminSchedulesProvider);
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Horario eliminado')),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = '$err'.replaceFirst('Bad state: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final connected = ref.watch(adminBackendRepositoryProvider) != null;
    final dir = connected
        ? const SchoolDirectory()
        : ref.watch(schoolDirectoryProvider);
    final me = ref.watch(authControllerProvider).user;
    final canDelete = me?.can('schedules.delete') ?? false;
    final muted =
        context.textTheme.bodySmall?.copyWith(color: palette.textMuted);

    String classLabel(SchoolClass c) {
      final group = dir.group(c.groupId)?.name ?? '';
      final teacher = dir.person(c.teacherId)?.name;
      return [c.subject, group, if (teacher != null) teacher]
          .where((p) => p.isNotEmpty)
          .join(' · ');
    }

    final classes = [...dir.classes]
      ..sort((a, b) => classLabel(a).compareTo(classLabel(b)));
    final selectedClass = classes.where((c) => c.id == _classId).firstOrNull;

    Widget timeButton(String label, TimeOfDay? value, bool start) => Expanded(
          child: BrutalButton(
            onTap: () => _pick(start),
            icon: Icons.access_time_rounded,
            label: value == null ? label : '$label ${_fmt(value)}',
            color: palette.cardElevated,
            foreground: Theme.of(context).colorScheme.onSurface,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const FormLabel('Tipo'),
        Wrap(
          spacing: 4,
          children: [
            BrutalPill(
              compact: true,
              label: 'Clase',
              icon: Icons.menu_book_rounded,
              selected: !_isBreak,
              onTap: () => setState(() => _isBreak = false),
            ),
            BrutalPill(
              compact: true,
              label: 'Receso',
              icon: Icons.free_breakfast_rounded,
              selected: _isBreak,
              onTap: () => setState(() => _isBreak = true),
            ),
          ],
        ),
        if (!_isBreak) ...[
          const FormLabel('Clase (materia · grupo · maestro)'),
          if (connected)
            DirectoryPicker(
                kind: 'classes',
                selected: {if (_classId != null) _classId!},
                onChanged: (values) =>
                    setState(() => _classId = values.firstOrNull),
                onOption: (option) {
                  if (_room.text.trim().isEmpty) {
                    _room.text = option['room'] as String? ?? '';
                  }
                },)
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: selectedClass?.id,
              hint: const Text('Elige la clase'),
              decoration: const InputDecoration(isDense: true),
              items: [
                for (final c in classes)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(classLabel(c), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() {
                _classId = v;
                final c = classes.where((x) => x.id == v).firstOrNull;
                if (c != null && _room.text.trim().isEmpty) _room.text = c.room;
              }),
            ),
          const SizedBox(height: 12),
          BrutalTextField(
            controller: _room,
            label: 'Aula (opcional)',
            icon: Icons.meeting_room_rounded,
          ),
        ] else ...[
          const SizedBox(height: 12),
          BrutalTextField(
            controller: _label,
            label: 'Nombre del receso',
            icon: Icons.free_breakfast_rounded,
          ),
          const FormLabel('Aplica a'),
          if (connected) ...[
            if (_groupId == null) const Text('Todos los grupos'),
            DirectoryPicker(
                kind: 'groups',
                selected: {if (_groupId != null) _groupId!},
                onChanged: (values) =>
                    setState(() => _groupId = values.firstOrNull),),
          ] else
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue:
                  dir.groups.any((g) => g.id == _groupId) ? _groupId : null,
              decoration: const InputDecoration(isDense: true),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todos los grupos'),
                ),
                for (final g in dir.groups)
                  DropdownMenuItem<String?>(value: g.id, child: Text(g.name)),
              ],
              onChanged: (v) => setState(() => _groupId = v),
            ),
        ],
        FormLabel(_isNew ? 'Días de la semana' : 'Día'),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final d in scheduleWeekdays)
              BrutalPill(
                compact: true,
                label: d.$2,
                selected: _days.contains(d.$1),
                onTap: () => setState(() {
                  if (_isNew) {
                    _days.contains(d.$1) ? _days.remove(d.$1) : _days.add(d.$1);
                  } else {
                    _days = {d.$1};
                  }
                }),
              ),
          ],
        ),
        const FormLabel('Horario'),
        Row(
          children: [
            timeButton('Inicio', _start, true),
            const SizedBox(width: 10),
            timeButton('Fin', _end, false),
          ],
        ),
        const FormLabel('Turno (opcional)'),
        Wrap(
          spacing: 4,
          children: [
            for (final s in scheduleShifts)
              BrutalPill(
                compact: true,
                label: s.$2,
                selected: _shift == s.$1,
                onTap: () =>
                    setState(() => _shift = _shift == s.$1 ? null : s.$1),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'El maestro y el grupo salen de la clase. El sistema no permite '
          'choques de grupo, maestro ni aula.',
          style: muted,
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text(
            _error!,
            style: context.textTheme.bodySmall?.copyWith(color: palette.danger),
          ),
          const SizedBox(height: 10),
        ],
        BrutalButton(
          expand: true,
          onTap: _saving ? () {} : _save,
          icon: Icons.check_rounded,
          label: _saving
              ? 'Guardando…'
              : _isNew
                  ? 'Guardar horario'
                  : 'Guardar cambios',
        ),
        if (!_isNew && canDelete) ...[
          const SizedBox(height: 10),
          BrutalButton(
            expand: true,
            onTap: _delete,
            icon: Icons.delete_outline_rounded,
            label: 'Eliminar',
            color: palette.danger,
          ),
        ],
      ],
    );
  }
}
