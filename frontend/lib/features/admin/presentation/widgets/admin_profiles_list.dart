import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../shared/models/app_role.dart';
import '../../data/admin_backend_repository.dart';
import '../../data/admin_permissions.dart';
import '../../data/admin_profile.dart';
import 'admin_widgets.dart';
import 'admin_profile_form.dart';

class AdminProfilesList extends ConsumerStatefulWidget {
  const AdminProfilesList({super.key, required this.canEdit});
  final bool canEdit;
  @override
  ConsumerState<AdminProfilesList> createState() => _AdminProfilesListState();
}

class _AdminProfilesListState extends ConsumerState<AdminProfilesList> {
  int _page = 1;
  String _query = '';
  Timer? _searchTimer;
  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profiles =
        ref.watch(adminProfilesProvider((search: _query, page: _page)));
    return Column(children: [
      AdminSearchField(
          hint: 'Buscar perfil administrativo…',
          onChanged: (value) {
            _searchTimer?.cancel();
            _searchTimer = Timer(const Duration(milliseconds: 300), () {
              if (mounted) {
                setState(() {
                  _query = value.trim();
                  _page = 1;
                });
              }
            });
          },),
      const SizedBox(height: 12),
      profiles.when(
        loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),),
        error: (e, _) => ErrorStateView(
            message: '$e',
            onRetry: () => ref.invalidate(adminProfilesProvider),),
        data: (result) => Column(children: [
          if (result.items.isEmpty)
            const EmptyState(
                icon: Icons.admin_panel_settings_rounded,
                title: 'Sin perfiles administrativos',
                subtitle: 'No hay perfiles con ese criterio.',),
          for (final p in result.items)
            AdminTile(
                title: p.fullName,
                subtitle: p.email,
                caption:
                    '${_roleLabel(p.roleCode)} · ${_summary(p)}${p.active ? '' : ' · Inactivo'}',
                color: roleColor(context, _appRole(p.roleCode)),
                leadingText: p.initials,
                dimmed: !p.active,
                onTap: widget.canEdit
                    ? () => showAdminProfileSheet(context, existing: p)
                    : null,),
          if (result.pageInfo.totalPages > 1)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                  tooltip: 'Página anterior',
                  onPressed: result.pageInfo.hasPreviousPage
                      ? () => setState(() => _page--)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),),
              Text('${result.pageInfo.page} / ${result.pageInfo.totalPages}'),
              IconButton(
                  tooltip: 'Página siguiente',
                  onPressed: result.pageInfo.hasNextPage
                      ? () => setState(() => _page++)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),),
            ],),
        ],),
      ),
    ],);
  }

  static String _roleLabel(String code) => adminProfileRoles
      .firstWhere((r) => r.$1 == code, orElse: () => (code, code))
      .$2;
  static String _summary(AdminProfile p) =>
      p.customized ? '${p.permissions.length} permisos' : 'Acceso completo';
  static AppRole _appRole(String code) => switch (code) {
        'coordinator' => AppRole.coordinator,
        'director' => AppRole.director,
        _ => AppRole.admin
      };
}
