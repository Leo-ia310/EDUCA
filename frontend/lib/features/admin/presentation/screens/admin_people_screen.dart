import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/paginated_response.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../shared/models/app_role.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/admin_backend_repository.dart';
import '../../data/school_directory.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/person_form.dart';

/// CRUD de personas de un rol: Maestros, Alumnos o Padres/Tutores.
class AdminPeopleScreen extends ConsumerStatefulWidget {
  const AdminPeopleScreen(
      {super.key, required this.role, this.reportCards = false,});

  final AppRole role;
  final bool reportCards;

  @override
  ConsumerState<AdminPeopleScreen> createState() => _AdminPeopleScreenState();
}

class _AdminPeopleScreenState extends ConsumerState<AdminPeopleScreen> {
  String _query = '';
  int _page = 1;
  Timer? _searchTimer;

  void _search(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _query = value.trim();
          _page = 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  Future<void> _edit({Person? person}) async {
    await showPersonSheet(context, existing: person, role: widget.role);
    if (mounted) ref.invalidate(adminPeoplePageProvider);
  }

  String get _title => widget.reportCards
      ? 'Boletines'
      : switch (widget.role) {
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

  Set<String> _studentClassIds(Person p, SchoolDirectory dir) {
    if (p.classIds.isNotEmpty) return p.classIds;
    final groupId = p.groupId;
    if (groupId == null) return const <String>{};
    return dir.classesOfGroup(groupId).map((c) => c.id).toSet();
  }

  String _subtitle(Person p, SchoolDirectory dir) {
    switch (widget.role) {
      case AppRole.teacher:
        if (p.classLabels.isNotEmpty) {
          return '${p.classLabels.length} clases asignadas · ${p.classLabels.join(' · ')}';
        }
        final cls = dir.classesOfTeacher(p.id);
        if (cls.isEmpty) return 'Sin clases asignadas';
        final countLabel = cls.length == 1
            ? '1 clase asignada'
            : '${cls.length} clases asignadas';
        final names = cls
            .map(
              (c) => '${c.subject} (${dir.group(c.groupId)?.name ?? '—'})',
            )
            .join(' · ');
        return '$countLabel · $names';
      case AppRole.student:
        final g = p.groupName ?? dir.group(p.groupId)?.name ?? 'Sin salón';
        final count = _studentClassIds(p, dir).length;
        final label = count == 1 ? '1 clase' : '$count clases';
        return '$g · $label';
      case AppRole.parent:
        if (p.childNames.isNotEmpty) return p.childNames.join(', ');
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
    final repo = ref.watch(adminBackendRepositoryProvider);
    if (repo != null) {
      final result = ref.watch(widget.reportCards
          ? adminDirectoryPeoplePageProvider(
              (role: widget.role, search: _query, page: _page, groupId: null),)
          : adminPeoplePageProvider(
              (role: widget.role, search: _query, page: _page),),);
      return _buildList(
          context, result.valueOrNull?.items ?? [], const SchoolDirectory(),
          remote: true,
          loading: result.isLoading,
          error: result.error,
          pageInfo: result.valueOrNull?.pageInfo,);
    }
    final dir = ref.watch(schoolDirectoryProvider);
    final people = dir.byRole(widget.role)
      ..sort((a, b) => a.name.compareTo(b.name));
    return _buildList(context, people, dir);
  }

  Widget _buildList(
    BuildContext context,
    List<Person> list,
    SchoolDirectory dir, {
    bool remote = false,
    bool loading = false,
    Object? error,
    PageInfo? pageInfo,
  }) {
    final user = ref.watch(authControllerProvider).user;
    final module = widget.role == AppRole.teacher ? 'teachers' : 'students';
    final canCreate =
        !widget.reportCards && (user?.can('$module.create') ?? false);
    final canEdit = user?.can('$module.edit') ?? false;
    final q = _query.trim().toLowerCase();
    final sorted =
        remote ? list : ([...list]..sort((a, b) => a.name.compareTo(b.name)));
    final shown = remote || q.isEmpty
        ? sorted
        : sorted
            .where(
              (p) =>
                  p.name.toLowerCase().contains(q) ||
                  p.email.toLowerCase().contains(q),
            )
            .toList();
    final color = roleColor(context, widget.role);

    return StudentDetailScaffold(
      title: _title,
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canCreate) ...[
            BrutalButton(
              expand: true,
              onTap: () => _edit(),
              icon: Icons.person_add_alt_1_rounded,
              label: 'Nuevo $_singular',
            ),
            const SizedBox(height: 14),
          ],
          AdminSearchField(
            hint: 'Buscar por nombre o correo…',
            onChanged: _search,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '${pageInfo?.total ?? list.length} ${q.isEmpty ? 'registrados' : 'resultados'}',
              style: context.textTheme.labelMedium?.copyWith(
                color: context.palette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (error != null) ...[
            ErrorStateView(message: '$error'),
            TextButton(
                onPressed: () => ref.invalidate(adminPeoplePageProvider),
                child: const Text('Reintentar'),),
          ] else if (shown.isEmpty)
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
                onTap: widget.reportCards
                    ? () => context.push(
                        '${Routes.reports}?studentId=${Uri.encodeComponent(p.id)}',)
                    : canEdit
                        ? () => _edit(person: p)
                        : null,
              ),
          if (pageInfo != null && pageInfo.totalPages > 1)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                  tooltip: 'Página anterior',
                  onPressed: loading || !pageInfo.hasPreviousPage
                      ? null
                      : () => setState(() => _page--),
                  icon: const Icon(Icons.chevron_left_rounded),),
              Text('${pageInfo.page} / ${pageInfo.totalPages}'),
              IconButton(
                  tooltip: 'Página siguiente',
                  onPressed: loading || !pageInfo.hasNextPage
                      ? null
                      : () => setState(() => _page++),
                  icon: const Icon(Icons.chevron_right_rounded),),
            ],),
        ],
      ),
    );
  }
}
