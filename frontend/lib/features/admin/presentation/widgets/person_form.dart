import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../shared/models/app_role.dart';
import '../../data/admin_backend_repository.dart';
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
  late final TextEditingController _username;
  late final TextEditingController _password;
  late AppRole _role;
  late bool _active;
  String? _groupId;
  late Set<String> _classIds;
  late Set<String> _childIds;
  late Set<String> _teacherClassIds; // clases asignadas (maestro)
  bool _teacherClassIdsHydrated = false;
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _email = TextEditingController(text: p?.email ?? '');
    _phone = TextEditingController(text: p?.phone ?? '');
    _username = TextEditingController();
    _password = TextEditingController();
    _role = widget.initialRole;
    _active = p?.active ?? true;
    _groupId = p?.groupId;
    _classIds = {...?p?.classIds};
    _childIds = {...?p?.childIds};
    _teacherClassIds = <String>{};
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validate() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final connected = ref.read(adminBackendRepositoryProvider) != null;
    setState(() {
      _nameError = name.isEmpty ? 'El nombre es obligatorio' : null;
      _emailError = connected && email.isEmpty
          ? 'El correo es obligatorio para crear acceso'
          : email.isNotEmpty &&
                  !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
              ? 'Correo no válido'
              : null;
      _passwordError = widget.existing == null && _password.text.length < 6
          ? 'Mínimo 6 caracteres'
          : null;
    });
    return _nameError == null && _emailError == null && _passwordError == null;
  }

  void _hydrateTeacherClassIds(SchoolDirectory dir) {
    if (_teacherClassIdsHydrated || widget.existing == null) return;
    _teacherClassIdsHydrated = true;
    if (_role == AppRole.teacher) {
      _teacherClassIds =
          dir.classesOfTeacher(widget.existing!.id).map((c) => c.id).toSet();
    }
  }

  Future<void> _save() async {
    if (!_validate()) return;
    final repo = ref.read(adminBackendRepositoryProvider);
    if (repo != null) {
      await _saveBackend(repo);
      return;
    }
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

  Future<void> _saveBackend(AdminBackendRepository repo) async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final parts = _name.text.trim().split(RegExp(r'\s+'));
      final firstName = parts.isEmpty ? _name.text.trim() : parts.first;
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '—';
      final resource = switch (_role) {
        AppRole.teacher => 'teachers',
        AppRole.student => 'students',
        AppRole.parent => 'parents',
        _ => 'students',
      };
      final payload = <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'username':
            _username.text.trim().isEmpty ? null : _username.text.trim(),
        'active': _active,
        if (widget.existing == null) 'password': _password.text,
      };
      if (_role == AppRole.teacher) {
        payload['teacherCode'] = 'DOC-${DateTime.now().millisecondsSinceEpoch}';
        payload['classIds'] = _teacherClassIds.toList();
      } else if (_role == AppRole.student) {
        payload['studentCode'] = 'EST-${DateTime.now().millisecondsSinceEpoch}';
        payload['groupId'] = _groupId;
        payload['classIds'] = _classIds.toList();
      } else if (_role == AppRole.parent) {
        payload['isEmergencyContact'] = true;
        payload['childIds'] = _childIds.toList();
      }

      if (widget.existing == null) {
        await repo.createPeople(resource, payload);
      } else {
        await repo.updatePeople(resource, widget.existing!.id, payload);
      }
      ref.invalidate(adminPeopleByRoleProvider(_role));
      ref.invalidate(adminSchoolDirectoryProvider);
      await ref.read(adminSchoolDirectoryProvider.future);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveError = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final p = widget.existing!;
    if (!await confirmDelete(context, p.name)) return;
    ref.read(schoolDirectoryProvider.notifier).removePerson(p.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminBackendRepositoryProvider);
    final remote =
        repo == null ? null : ref.watch(adminSchoolDirectoryProvider);
    final SchoolDirectory dir =
        remote?.asData?.value ?? ref.watch(schoolDirectoryProvider);
    _hydrateTeacherClassIds(dir);
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
        if (widget.existing == null) ...[
          const SizedBox(height: 12),
          BrutalTextField(
            controller: _username,
            label: 'Usuario para iniciar sesión (opcional)',
            icon: Icons.badge_rounded,
          ),
          const SizedBox(height: 12),
          BrutalTextField(
            controller: _password,
            label: 'Contraseña inicial',
            icon: Icons.lock_rounded,
            obscureText: true,
            errorText: _passwordError,
          ),
        ],
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
                    _groupId = c.groupId;
                    _classIds = dir
                        .classesOfGroup(c.groupId)
                        .map((schoolClass) => schoolClass.id)
                        .toSet();
                  }),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'La inscripción se guarda por salón; sus clases se cargan automáticamente desde ese salón.',
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.palette.textMuted),
            ),
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
        if (_saveError != null) ...[
          Text(
            _saveError!,
            style: context.textTheme.bodySmall
                ?.copyWith(color: context.palette.danger),
          ),
          const SizedBox(height: 10),
        ],
        BrutalButton(
          expand: true,
          onTap: _saving ? () {} : () => _save(),
          icon: _saving ? Icons.hourglass_top_rounded : Icons.save_rounded,
          label: _saving
              ? 'Guardando…'
              : widget.existing == null
                  ? 'Crear acceso'
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
