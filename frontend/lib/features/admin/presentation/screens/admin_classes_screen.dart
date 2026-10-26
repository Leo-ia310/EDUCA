import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/paginated_response.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../shared/models/app_role.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/admin_backend_repository.dart';
import '../../data/school_directory.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/class_form.dart';
import '../widgets/page_controls.dart';
import '../../../../core/utils/plural.dart';

/// CRUD de clases y de sus asignaciones: cada clase muestra su salón y su
/// maestro, y se puede cambiar de maestro o de salón al editarla. Alterna
/// entre "Por salón" y "Por maestro".
class AdminClassesScreen extends ConsumerStatefulWidget {
  const AdminClassesScreen({super.key});

  @override
  ConsumerState<AdminClassesScreen> createState() => _AdminClassesScreenState();
}

class _AdminClassesScreenState extends ConsumerState<AdminClassesScreen> {
  bool _byGroup = true;
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
    final repo = ref.watch(adminBackendRepositoryProvider);
    if (repo != null) {
      final result = ref.watch(adminCatalogProvider(
          (kind: 'classes', search: _query, page: _page, groupId: null),),);
      return _buildWithDirectory(
          result.valueOrNull?.directory ?? const SchoolDirectory(),
          loading: result.isLoading,
          error: result.error,
          pageInfo: result.valueOrNull?.pageInfo,);
    }
    return _buildWithDirectory(ref.watch(schoolDirectoryProvider));
  }

  Widget _buildWithDirectory(SchoolDirectory dir,
      {bool loading = false, Object? error, PageInfo? pageInfo,}) {
    final palette = context.palette;

    Widget tile(
      SchoolClass c, {
      bool showGroup = true,
      bool showTeacher = true,
    }) {
      final teacher = dir.person(c.teacherId)?.name ?? 'Sin maestro asignado';
      final group = dir.group(c.groupId)?.name ?? '—';
      return AdminTile(
        title: c.subject,
        subtitle: [
          if (showTeacher) teacher,
          if (showGroup) group,
        ].join(' · '),
        caption: c.room.isEmpty ? null : c.room,
        color: subjectTone(c.subject),
        leadingIcon: Icons.menu_book_rounded,
        onTap:
            ref.read(authControllerProvider).user?.can('classes.edit') ?? false
                ? () async {
                    await showClassSheet(context, existing: c);
                    if (mounted) ref.invalidate(adminCatalogProvider);
                  }
                : null,
      );
    }

    final sections = <Widget>[];
    if (_byGroup) {
      for (final g in dir.groups) {
        final cls = dir.classesOfGroup(g.id);
        if (cls.isEmpty) continue;
        sections
          ..add(SectionHeader(title: g.name, accent: false))
          ..add(const SizedBox(height: 8))
          ..addAll([for (final c in cls) tile(c, showGroup: false)])
          ..add(const SizedBox(height: 10));
      }
    } else {
      final teachers = dir.byRole(AppRole.teacher);
      for (final t in teachers) {
        final cls = dir.classesOfTeacher(t.id);
        if (cls.isEmpty) continue;
        sections
          ..add(SectionHeader(title: t.name, accent: false))
          ..add(const SizedBox(height: 8))
          ..addAll([for (final c in cls) tile(c, showTeacher: false)])
          ..add(const SizedBox(height: 10));
      }
      final orphan = dir.classes.where((c) => c.teacherId == null).toList();
      if (orphan.isNotEmpty) {
        sections
          ..add(const SectionHeader(title: 'Sin maestro', accent: false))
          ..add(const SizedBox(height: 8))
          ..addAll([for (final c in orphan) tile(c, showTeacher: false)]);
      }
    }

    return StudentDetailScaffold(
      title: 'Clases y asignaciones',
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ref.watch(authControllerProvider).user?.can('classes.create') ??
              false) ...[
            BrutalButton(
              expand: true,
              onTap: () async {
                await showClassSheet(context);
                if (mounted) ref.invalidate(adminCatalogProvider);
              },
              icon: Icons.add_rounded,
              label: 'Nueva clase',
            ),
            const SizedBox(height: 14),
          ],
          if (ref.watch(adminBackendRepositoryProvider) != null)
            AdminSearchField(
                hint: 'Buscar materia, salón o maestro…',
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
          Row(
            children: [
              BrutalPill(
                label: 'Por salón',
                selected: _byGroup,
                onTap: () => setState(() => _byGroup = true),
              ),
              const SizedBox(width: 6),
              BrutalPill(
                label: 'Por maestro',
                selected: !_byGroup,
                onTap: () => setState(() => _byGroup = false),
              ),
              const Spacer(),
              Text(
                plural(pageInfo?.total ?? dir.classes.length, 'clase'),
                style: context.textTheme.labelMedium?.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (error != null)
            ErrorStateView(
                message: '$error',
                onRetry: () => ref.invalidate(adminCatalogProvider),)
          else if (sections.isEmpty)
            const EmptyState(
              icon: Icons.menu_book_rounded,
              title: 'Sin clases',
              subtitle: 'Crea la primera clase.',
            )
          else
            ...sections,
          if (pageInfo != null)
            PageControls(
                pageInfo: pageInfo,
                onPage: (page) => setState(() => _page = page),),
        ],
      ),
    );
  }
}
