import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../shared/models/app_role.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../data/school_directory.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/person_form.dart';

String _permissions(AppRole r) => switch (r) {
      AppRole.director =>
        'Control total del colegio: personas, clases, notas, pagos y roles.',
      AppRole.admin =>
        'Gestión administrativa: personas, clases, pagos y comunicados.',
      AppRole.coordinator =>
        'Seguimiento académico: clases, horarios, notas y asistencia.',
      AppRole.teacher =>
        'Sus clases: tareas, exámenes, asistencia y calificaciones.',
      AppRole.parent => 'Seguimiento de sus hijos: notas, pagos y mensajes.',
      AppRole.student => 'Sus tareas, notas, horario y asistencia.',
    };

/// Roles y perfiles: resumen de cada rol (con su cantidad de perfiles) y CRUD
/// de los perfiles/cuentas, incluido el cambio de rol y el alta de perfiles
/// nuevos (padre, alumno, maestro, coordinador…).
class AdminRolesScreen extends ConsumerStatefulWidget {
  const AdminRolesScreen({super.key});

  @override
  ConsumerState<AdminRolesScreen> createState() => _AdminRolesScreenState();
}

class _AdminRolesScreenState extends ConsumerState<AdminRolesScreen> {
  AppRole? _filter;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final dir = ref.watch(schoolDirectoryProvider);
    final palette = context.palette;
    final q = _query.trim().toLowerCase();
    final profiles = dir.people
        .where((p) => _filter == null || p.role == _filter)
        .where(
          (p) =>
              q.isEmpty ||
              p.name.toLowerCase().contains(q) ||
              p.email.toLowerCase().contains(q),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return StudentDetailScaffold(
      title: 'Roles y perfiles',
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutalButton(
            expand: true,
            onTap: () => showPersonSheet(context, pickRole: true),
            icon: Icons.person_add_alt_1_rounded,
            label: 'Nuevo perfil',
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Roles', accent: false),
          const SizedBox(height: 8),
          for (final r in AppRole.values)
            _RoleCard(
              role: r,
              count: dir.byRole(r).length,
              selected: _filter == r,
              onTap: () => setState(() => _filter = _filter == r ? null : r),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: SectionHeader(title: 'Perfiles', accent: false),
              ),
              if (_filter != null)
                TextButton(
                  onPressed: () => setState(() => _filter = null),
                  child: Text('Ver todos (${_filter!.label})'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          AdminSearchField(
            hint: 'Buscar perfil…',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          if (profiles.isEmpty)
            const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Sin perfiles',
              subtitle: 'No hay perfiles con ese criterio.',
            )
          else
            for (final p in profiles)
              AdminTile(
                title: p.name,
                subtitle: p.email,
                caption: p.active ? p.role.label : '${p.role.label} · Inactivo',
                color: roleColor(p.role),
                leadingText: p.initials,
                dimmed: !p.active,
                onTap: () => showPersonSheet(
                  context,
                  existing: p,
                  pickRole: true,
                ),
              ),
          const SizedBox(height: 4),
          Text(
            'Los roles son fijos de la plataforma; aquí controlas qué perfiles '
            'tiene cada uno y creas o editas cada perfil.',
            style:
                context.textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final AppRole role;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(roleColor(role));
    final ink = Brutal.ink(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BrutalBox(
        onTap: onTap,
        color: selected ? s.vivid.withValues(alpha: 0.35) : s.surface,
        radius: Radii.md,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: s.vivid,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: ink, width: Brutal.border),
              ),
              child: Icon(roleIcon(role), color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.label,
                    style: context.textTheme.titleSmall?.copyWith(
                      color: s.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _permissions(role),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: s.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: ink, width: Brutal.border),
              ),
              child: Text(
                '$count',
                style: context.textTheme.titleSmall?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
