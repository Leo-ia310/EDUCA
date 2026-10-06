import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../shared/models/app_role.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../data/school_directory.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/person_form.dart';

/// CRUD de personas de un rol: Maestros, Alumnos o Padres/Tutores.
class AdminPeopleScreen extends ConsumerStatefulWidget {
  const AdminPeopleScreen({super.key, required this.role});

  final AppRole role;

  @override
  ConsumerState<AdminPeopleScreen> createState() => _AdminPeopleScreenState();
}

class _AdminPeopleScreenState extends ConsumerState<AdminPeopleScreen> {
  String _query = '';

  String get _title => switch (widget.role) {
        AppRole.teacher => 'Maestros',
        AppRole.student => 'Alumnos',
        AppRole.parent => 'Padres y tutores',
        _ => widget.role.label,
      };

  String get _singular => switch (widget.role) {
        AppRole.teacher => 'maestro',
        AppRole.student => 'alumno',
        AppRole.parent => 'padre o tutor',
        _ => widget.role.label.toLowerCase(),
      };

  String _subtitle(Person p, SchoolDirectory dir) {
    switch (widget.role) {
      case AppRole.teacher:
        final cls = dir.classesOfTeacher(p.id);
        return cls.isEmpty
            ? 'Sin clases asignadas'
            : cls
                .map(
                  (c) => '${c.subject} (${dir.group(c.groupId)?.name ?? '—'})',
                )
                .join(' · ');
      case AppRole.student:
        final g = dir.group(p.groupId)?.name ?? 'Sin salón';
        return '$g · ${p.classIds.length} clases';
      case AppRole.parent:
        final kids = p.childIds
            .map((id) => dir.person(id)?.name)
            .whereType<String>()
            .toList();
        return kids.isEmpty ? 'Sin alumnos vinculados' : kids.join(', ');
      default:
        return p.email;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dir = ref.watch(schoolDirectoryProvider);
    final q = _query.trim().toLowerCase();
    final list = dir.byRole(widget.role)
      ..sort((a, b) => a.name.compareTo(b.name));
    final shown = q.isEmpty
        ? list
        : list
            .where(
              (p) =>
                  p.name.toLowerCase().contains(q) ||
                  p.email.toLowerCase().contains(q),
            )
            .toList();
    final color = roleColor(widget.role);

    return StudentDetailScaffold(
      title: _title,
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutalButton(
            expand: true,
            onTap: () => showPersonSheet(context, role: widget.role),
            icon: Icons.person_add_alt_1_rounded,
            label: 'Nuevo $_singular',
          ),
          const SizedBox(height: 14),
          AdminSearchField(
            hint: 'Buscar por nombre o correo…',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '${list.length} registrados',
              style: context.textTheme.labelMedium?.copyWith(
                color: context.palette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (shown.isEmpty)
            const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Sin resultados',
              subtitle: 'No hay registros con ese criterio.',
            )
          else
            for (final p in shown)
              AdminTile(
                title: p.name,
                subtitle: _subtitle(p, dir),
                caption: p.active ? null : 'Inactivo',
                color: color,
                leadingText: p.initials,
                dimmed: !p.active,
                onTap: () => showPersonSheet(context, existing: p),
              ),
        ],
      ),
    );
  }
}
