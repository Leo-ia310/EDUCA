import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../shared/models/app_role.dart';
import '../../data/school_directory.dart';
import 'admin_widgets.dart';

/// Abre la hoja de alta/edición de una persona.
///
/// - [existing] != null → edición (con botón de eliminar).
/// - [role] fija el rol de un alta nueva (Maestros, Alumnos, Padres).
/// - [pickRole] permite elegir el rol (panel de Roles y perfiles).
Future<void> showPersonSheet(
  BuildContext context, {
  Person? existing,
  AppRole? role,
  bool pickRole = false,
}) {
  final r = existing?.role ?? role ?? AppRole.student;
  final label = pickRole ? 'perfil' : r.label.toLowerCase();
  return showBrutalSheet<void>(
    context,
    title: existing == null ? 'Nuevo $label' : 'Editar ${existing.name}',
    child: _PersonForm(existing: existing, initialRole: r, pickRole: pickRole),
  );
}

class _PersonForm extends ConsumerStatefulWidget {
  const _PersonForm({
    required this.existing,
    required this.initialRole,
    required this.pickRole,
  });

  final Person? existing;
  final AppRole initialRole;
  final bool pickRole;

  @override
  ConsumerState<_PersonForm> createState() => _PersonFormState();
}

class _PersonFormState extends ConsumerState<_PersonForm> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late AppRole _role;
  late bool _active;
  String? _groupId;
  late Set<String> _classIds;
  late Set<String> _childIds;
  late Set<String> _teacherClassIds; // clases asignadas (maestro)
  String? _nameError;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _email = TextEditingController(text: p?.email ?? '');
    _phone = TextEditingController(text: p?.phone ?? '');
    _role = widget.initialRole;
    _active = p?.active ?? true;
    _groupId = p?.groupId;
    _classIds = {...?p?.classIds};
    _childIds = {...?p?.childIds};
    final dir = ref.read(schoolDirectoryProvider);
    _teacherClassIds = p == null
        ? <String>{}
        : dir.classesOfTeacher(p.id).map((c) => c.id).toSet();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool _validate() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'El nombre es obligatorio' : null;
      _emailError = email.isNotEmpty &&
              !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
          ? 'Correo no válido'
          : null;
    });
    return _nameError == null && _emailError == null;
  }

  void _save() {
    if (!_validate()) return;
    final store = ref.read(schoolDirectoryProvider.notifier);
    final old = widget.existing;
    final isStudent = _role == AppRole.student;
    final isParent = _role == AppRole.parent;

    final draft = Person(
      id: old?.id ?? '',
      name: _name.text.trim(),
      role: _role,
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      active: _active,
      groupId: isStudent ? _groupId : null,
      classIds: isStudent ? _classIds : const {},
      childIds: isParent ? _childIds : const {},
    );

    final saved = old == null ? store.addPerson(draft) : draft;
    if (old != null) store.updatePerson(draft);

    // Asignaciones de clases del maestro (cambiar de maestro una clase).
    final dir = ref.read(schoolDirectoryProvider);
    for (final c in dir.classes) {
      final should =
          _role == AppRole.teacher && _teacherClassIds.contains(c.id);
      if (should && c.teacherId != saved.id) {
        store.assignTeacher(c.id, saved.id);
      } else if (!should && c.teacherId == saved.id) {
        store.assignTeacher(c.id, null);
      }
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final p = widget.existing!;
    if (!await confirmDelete(context, p.name)) return;
    ref.read(schoolDirectoryProvider.notifier).removePerson(p.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dir = ref.watch(schoolDirectoryProvider);
    final students = dir.byRole(AppRole.student);

    String classLabel(SchoolClass c) =>
        '${c.subject} · ${dir.group(c.groupId)?.name ?? '—'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.pickRole) ...[
          const FormLabel('Rol'),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final r in AppRole.values)
                BrutalPill(
                  compact: true,
                  label: r.label,
                  icon: roleIcon(r),
                  selected: _role == r,
                  onTap: () => setState(() => _role = r),
                ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 4),
        BrutalTextField(
          controller: _name,
          label: 'Nombre completo',
          icon: Icons.person_rounded,
          errorText: _nameError,
        ),
        const SizedBox(height: 12),
        BrutalTextField(
          controller: _email,
          label: 'Correo',
          icon: Icons.mail_rounded,
          keyboardType: TextInputType.emailAddress,
          errorText: _emailError,
        ),
        const SizedBox(height: 12),
        BrutalTextField(
          controller: _phone,
          label: 'Teléfono',
          icon: Icons.phone_rounded,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _active,
          onChanged: (v) => setState(() => _active = v),
          title: const Text('Perfil activo'),
        ),
        if (_role == AppRole.student) ...[
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
                  onTap: () => setState(() {
                    _groupId = g.id;
                    // Al cambiar de salón se inscribe en sus clases.
                    _classIds =
                        dir.classesOfGroup(g.id).map((c) => c.id).toSet();
                  }),
                ),
            ],
          ),
          const FormLabel('Clases inscritas'),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final c in dir.classes)
                BrutalPill(
                  compact: true,
                  label: classLabel(c),
                  selected: _classIds.contains(c.id),
                  onTap: () => setState(() {
                    _classIds.contains(c.id)
                        ? _classIds.remove(c.id)
                        : _classIds.add(c.id);
                  }),
                ),
            ],
          ),
        ],
        if (_role == AppRole.parent) ...[
          const FormLabel('Hijos / alumnos a cargo'),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final s in students)
                BrutalPill(
                  compact: true,
                  label: s.name,
                  selected: _childIds.contains(s.id),
                  onTap: () => setState(() {
                    _childIds.contains(s.id)
                        ? _childIds.remove(s.id)
                        : _childIds.add(s.id);
                  }),
                ),
            ],
          ),
        ],
        if (_role == AppRole.teacher) ...[
          const FormLabel('Clases asignadas'),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final c in dir.classes)
                BrutalPill(
                  compact: true,
                  label: classLabel(c),
                  selected: _teacherClassIds.contains(c.id),
                  onTap: () => setState(() {
                    _teacherClassIds.contains(c.id)
                        ? _teacherClassIds.remove(c.id)
                        : _teacherClassIds.add(c.id);
                  }),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Al marcar una clase que tiene otro maestro, pasa a este.',
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.palette.textMuted),
            ),
          ),
        ],
        const SizedBox(height: 20),
        BrutalButton(
          expand: true,
          onTap: _save,
          icon: Icons.save_rounded,
          label: widget.existing == null ? 'Crear' : 'Guardar cambios',
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
