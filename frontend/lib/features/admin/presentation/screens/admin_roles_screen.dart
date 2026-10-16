import 'package:go_router/go_router.dart';
import '../../../../core/routing/route_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../shared/models/app_role.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/admin_backend_repository.dart';
import '../../data/admin_permissions.dart';
import '../../data/admin_profile.dart';
import '../../data/school_directory.dart';
import '../widgets/admin_profile_form.dart';
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

  Future<void> _openPersonSheet(
    BuildContext context, {
    Person? existing,
  }) async {
    await showPersonSheet(context, existing: existing, pickRole: true);
    if (!mounted) return;
    ref.invalidate(adminSchoolDirectoryProvider);
    await ref.read(adminSchoolDirectoryProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminBackendRepositoryProvider);
    final remote =
        repo == null ? null : ref.watch(adminSchoolDirectoryProvider);
    final fallbackDir = ref.watch(schoolDirectoryProvider);

    if (remote != null) {
      return remote.when(
        loading: () => const StudentDetailScaffold(
          title: 'Roles y perfiles',
          bottomNav: false,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => StudentDetailScaffold(
          title: 'Roles y perfiles',
          bottomNav: false,
          child: ErrorStateView(message: '$error'),
        ),
        data: (dir) => _buildContent(context, dir),
      );
    }

    return _buildContent(context, fallbackDir);
  }

  Widget _buildContent(BuildContext context, SchoolDirectory dir) {
    final palette = context.palette;
    final connected = ref.watch(adminBackendRepositoryProvider) != null;
    final me = ref.watch(authControllerProvider).user;
    final canCreate = me?.can('roles.create') ?? false;
    final canEdit = me?.can('roles.edit') ?? false;
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
          if (canEdit) ...[
            FilledButton.icon(
                onPressed: () => context.push(Routes.adminAccess),
                icon: const Icon(Icons.lock_person_rounded),
                label: const Text('Accesos de padres, alumnos y notas'),),
            const SizedBox(height: 16),
          ],
          if (canCreate) ...[
            BrutalButton(
              expand: true,
              onTap: () => connected
                  ? showAdminProfileSheet(context)
                  : _openPersonSheet(context),
              icon: Icons.person_add_alt_1_rounded,
              label: 'Nuevo perfil',
            ),
            const SizedBox(height: 20),
          ],
          if (connected) ...[
            const SectionHeader(
              title: 'Perfiles administrativos',
              accent: false,
            ),
            const SizedBox(height: 8),
            _AdminProfilesList(canEdit: canEdit, meId: me?.id),
            const SizedBox(height: 20),
          ],
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
                color: roleColor(context, p.role),
                leadingText: p.initials,
                dimmed: !p.active,
                onTap: canEdit && !p.role.isAdminPanel
                    ? () => _openPersonSheet(context, existing: p)
                    : null,
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
    final s = context.pastel(roleColor(context, role));
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

/// Perfiles con acceso al dashboard admin (administrador, supervisor /
/// coordinador, director) y cuántos permisos tiene cada uno.
class _AdminProfilesList extends ConsumerWidget {
  const _AdminProfilesList({required this.canEdit, required this.meId});

  final bool canEdit;
  final String? meId;

  static String _roleLabel(String code) => adminProfileRoles
      .firstWhere((r) => r.$1 == code, orElse: () => (code, code))
      .$2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(adminProfilesProvider);
    return profiles.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorStateView(
        message: '$e',
        onRetry: () => ref.invalidate(adminProfilesProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.admin_panel_settings_rounded,
            title: 'Sin perfiles administrativos',
            subtitle: 'Crea el primero con "Nuevo perfil".',
          );
        }
        return Column(
          children: [
            for (final p in list)
              AdminTile(
                title: p.fullName,
                subtitle: p.email,
                caption:
                    '${_roleLabel(p.roleCode)} · ${_summary(p)}${p.active ? '' : ' · Inactivo'}',
                color: roleColor(context, _appRole(p.roleCode)),
                leadingText: p.initials,
                dimmed: !p.active,
                onTap: canEdit
                    ? () => showAdminProfileSheet(context, existing: p)
                    : null,
              ),
          ],
        );
      },
    );
  }

  static String _summary(AdminProfile p) =>
      p.customized ? '${p.permissions.length} permisos' : 'Acceso completo';

  static AppRole _appRole(String code) => switch (code) {
        'coordinator' => AppRole.coordinator,
        'director' => AppRole.director,
        _ => AppRole.admin,
      };
}
