import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../shared/models/app_role.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../data/school_directory.dart';
import '../widgets/admin_widgets.dart';

/// Boletines: lista de estudiantes por salón; al tocar uno se abre su boletín.
class AdminReportCardsScreen extends ConsumerStatefulWidget {
  const AdminReportCardsScreen({super.key});

  @override
  ConsumerState<AdminReportCardsScreen> createState() =>
      _AdminReportCardsScreenState();
}

class _AdminReportCardsScreenState
    extends ConsumerState<AdminReportCardsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final dir = ref.watch(schoolDirectoryProvider);
    final q = _query.trim().toLowerCase();
    final students = dir
        .byRole(AppRole.student)
        .where((s) => q.isEmpty || s.name.toLowerCase().contains(q))
        .toList();

    final children = <Widget>[];
    for (final g in dir.groups) {
      final inGroup = students.where((s) => s.groupId == g.id).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (inGroup.isEmpty) continue;
      children
        ..add(SectionHeader(title: g.name, accent: false))
        ..add(const SizedBox(height: 8))
        ..addAll([
          for (final s in inGroup)
            AdminTile(
              title: s.name,
              subtitle: 'Ver boletín de notas',
              color: roleColor(AppRole.student),
              leadingText: s.initials,
              trailing: const Icon(Icons.picture_as_pdf_rounded),
              onTap: () => context.push(
                '${Routes.reports}?studentId=${int.tryParse(s.id) ?? 1001}',
              ),
            ),
        ])
        ..add(const SizedBox(height: 10));
    }

    return StudentDetailScaffold(
      title: 'Boletines',
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSearchField(
            hint: 'Buscar estudiante…',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 16),
          if (children.isEmpty)
            const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Sin resultados',
              subtitle: 'No hay estudiantes con ese criterio.',
            )
          else
            ...children,
          Text(
            'Los boletines de alumnos nuevos se generan cuando tienen notas.',
            style: context.textTheme.bodySmall
                ?.copyWith(color: context.palette.textMuted),
          ),
        ],
      ),
    );
  }
}
