import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/educa_fab.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../domain/entities.dart';
import '../controllers/assignments_list_controller.dart';
import '../widgets/assignment_card.dart';

class TeacherAssignmentsScreen extends ConsumerWidget {
  const TeacherAssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(teacherAssignmentsProvider);
    final filter = ref.watch(assignmentsFilterProvider);
    final palette = context.palette;

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Tareas y exámenes'),
      ),
      fab: EducaFab(
        onPressed: () =>
            context.push('${Routes.assignments}/new?classId=101'),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _FilterBar(filter: filter),
            Expanded(
              child: list.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (items) {
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Icons.assignment_outlined,
                      title: 'Sin tareas aún',
                      subtitle:
                          'Crea tu primera tarea o examen con el botón flotante.',
                      actionLabel: 'Crear tarea',
                      onAction: () => context.push(
                        '${Routes.assignments}/new?classId=101',
                      ),
                    );
                  }
                  return RefreshIndicator(
                    color: palette.limeDeep,
                    onRefresh: () async =>
                        ref.invalidate(teacherAssignmentsProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final a = items[i];
                        return AssignmentCard(
                          assignment: a,
                          onTap: () =>
                              context.push('${Routes.assignments}/${a.id}'),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter});
  final AssignmentsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final notifier = ref.read(assignmentsFilterProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => notifier.update((s) => s.copyWith(searchText: v)),
              decoration: InputDecoration(
                hintText: 'Buscar…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Abiertas'),
            selected: filter.onlyOpen,
            selectedColor: palette.limeSoft,
            checkmarkColor: palette.limeDeep,
            onSelected: (v) =>
                notifier.update((s) => s.copyWith(onlyOpen: v)),
          ),
        ],
      ),
    );
  }
}
