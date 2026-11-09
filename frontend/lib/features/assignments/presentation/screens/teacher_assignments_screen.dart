import '../../../../core/network/provider_cache.dart';
import '../widgets/assignment_load_more.dart';
import '../../../collaborations/providers.dart';
import '../../../../core/constants/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/entrance.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../dashboard/data/dashboard_data.dart';
import '../../../dashboard/data/mock_dashboard_data.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../../dashboard/providers.dart';
import '../../domain/assignment_page.dart';
import '../../domain/entities.dart';
import '../controllers/assignments_list_controller.dart';
import '../widgets/assignment_card.dart';

/// Más reciente primero (fecha de creación).
List<Assignment> _byCreation(Iterable<Assignment> items) =>
    [...items]..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

/// Clases del docente (propias y colaborativas).
List<TeacherClass> _teacherClasses(WidgetRef ref) {
  return (ref.watch(teacherDashboardProvider).scopedValue ??
          TeacherDashboardData.empty())
      .myClasses;
}

/// ¿Puede crear tareas? (en una clase concreta si [classId] viene).
bool _canCreate(WidgetRef ref, {int? classId}) {
  if (Env.isDemoMode) return true;
  final classes = (ref
          .watch(collaborationWorkspaceProvider)
          .valueOrNull?['classes'] as List?) ??
      const [];
  return classes.any(
    (c) =>
        (classId == null || (c['classId'] as num?)?.toInt() == classId) &&
        (c['permissions'] as List).contains('assignments.create'),
  );
}

/// Panel "Tareas y Exámenes" del docente. «Por clase»: tarjetas de clase con
/// sus totales reales (se calculan en la base, no dependen de páginas
/// cargadas) que abren la lista de esa clase. «Todas»: todo el historial por
/// fecha de creación, con filtros y carga automática al desplazarse.
class TeacherAssignmentsScreen extends ConsumerStatefulWidget {
  const TeacherAssignmentsScreen({super.key});

  @override
  ConsumerState<TeacherAssignmentsScreen> createState() =>
      _TeacherAssignmentsScreenState();
}

class _TeacherAssignmentsScreenState
    extends ConsumerState<TeacherAssignmentsScreen> {
  bool _byClass = true;
  AssignmentKind? _kind;
  bool _onlyOpen = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canCreate = _canCreate(ref);

    return StudentDetailScaffold(
      title: 'Tareas y Exámenes',
      scrollable: false,
      bottomNav: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _ModePill(
                      label: 'Por clase',
                      selected: _byClass,
                      onTap: () => setState(() => _byClass = true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModePill(
                      label: 'Todas',
                      selected: !_byClass,
                      onTap: () => setState(() => _byClass = false),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _byClass
                  ? _ClassCards(canCreate: canCreate, palette: palette)
                  : _AssignmentsList(
                      feed: (
                        classId: null,
                        kind: _kind,
                        onlyOpen: _onlyOpen,
                        search: '',
                      ),
                      kind: _kind,
                      onlyOpen: _onlyOpen,
                      onKind: (k) => setState(() => _kind = k),
                      onOnlyOpen: (v) => setState(() => _onlyOpen = v),
                      canCreate: canCreate,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjetas de clase con sus conteos reales (sin «Cargar más»).
class _ClassCards extends ConsumerWidget {
  const _ClassCards({required this.canCreate, required this.palette});
  final bool canCreate;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(teacherDashboardProvider);
    final counts = ref.watch(teacherAssignmentCountsProvider);
    final classes =
        _teacherClasses(ref).where((c) => c.classId != null).toList();

    if (dash.isLoading && !dash.isRefreshing && classes.isEmpty) {
      return const SkeletonList();
    }
    if (classes.isEmpty) {
      return EmptyState(
        icon: Icons.assignment_rounded,
        title: 'Sin clases asignadas',
        subtitle: 'Cuando tengas clases podrás crear tareas y exámenes.',
        actionLabel: canCreate ? 'Crear tarea' : null,
        onAction:
            canCreate ? () => context.push('${Routes.assignments}/new') : null,
      );
    }
    final byClass = counts.valueOrNull ?? const <int, ClassAssignmentCounts>{};
    return RefreshIndicator(
      color: palette.accentDeep,
      onRefresh: () async {
        ref.invalidate(teacherAssignmentCountsProvider);
        ref.invalidate(teacherDashboardProvider);
        await ref.read(teacherAssignmentCountsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (canCreate)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: BrutalButton(
                expand: true,
                onTap: () => context.push('${Routes.assignments}/new'),
                icon: Icons.add,
                label: 'Nueva tarea o examen',
              ),
            ),
          for (final (i, c) in classes.indexed)
            entranceItem(
              context,
              i,
              _ClassCard(
                teacherClass: c,
                counts: byClass[c.classId],
                loading: counts.isLoading && !counts.hasValue,
                onTap: () => context.push(
                  '${Routes.assignments}/class/${c.classId}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lista de tareas con filtros por tipo y «solo abiertas». Carga perezosa:
/// al llegar al final pide la siguiente página.
class _AssignmentsList extends ConsumerWidget {
  const _AssignmentsList({
    required this.feed,
    required this.kind,
    required this.onlyOpen,
    required this.onKind,
    required this.onOnlyOpen,
    required this.canCreate,
    this.emptyHint = 'Crea tu primera tarea o examen.',
  });

  final TeacherFeed feed;
  final AssignmentKind? kind;
  final bool onlyOpen;
  final ValueChanged<AssignmentKind?> onKind;
  final ValueChanged<bool> onOnlyOpen;
  final bool canCreate;
  final String emptyHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final provider = teacherAssignmentsProvider(feed);
    final list = ref.watch(provider);
    final paging = ref.watch(provider.notifier);
    final newRoute = feed.classId == null
        ? '${Routes.assignments}/new'
        : '${Routes.assignments}/new?classId=${feed.classId}';

    return list.when(
      loading: () => const SkeletonList(),
      error: (e, _) => ErrorStateView(
        message: '$e',
        onRetry: () => ref.invalidate(provider),
      ),
      data: (all) {
        final items = _byCreation(all);
        final filtering = kind != null || onlyOpen;
        return RefreshIndicator(
          color: palette.accentDeep,
          onRefresh: () async {
            ref.invalidate(provider);
            ref.invalidate(teacherAssignmentCountsProvider);
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: items.length + 3,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (canCreate)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: BrutalButton(
                            expand: true,
                            onTap: () => context.push(newRoute),
                            icon: Icons.add,
                            label: 'Nueva tarea o examen',
                          ),
                        ),
                      _FilterBar(
                        kind: kind,
                        onlyOpen: onlyOpen,
                        onKind: onKind,
                        onOnlyOpen: onOnlyOpen,
                      ),
                    ],
                  ),
                );
              }
              if (i == items.length + 1) {
                return items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: EmptyState(
                          icon: Icons.assignment_rounded,
                          title:
                              filtering ? 'Sin resultados' : 'Sin tareas aún',
                          subtitle: filtering
                              ? 'Ninguna tarea coincide con los filtros.'
                              : emptyHint,
                        ),
                      )
                    : const SizedBox.shrink();
              }
              if (i == items.length + 2) {
                return AssignmentLoadMore(controller: paging, auto: true);
              }
              return entranceItem(
                context,
                i - 1,
                _AssignmentTile(assignment: items[i - 1]),
              );
            },
          ),
        );
      },
    );
  }
}

/// Filtros: tipo (todas / tareas / exámenes…) y «solo abiertas».
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.kind,
    required this.onlyOpen,
    required this.onKind,
    required this.onOnlyOpen,
  });

  final AssignmentKind? kind;
  final bool onlyOpen;
  final ValueChanged<AssignmentKind?> onKind;
  final ValueChanged<bool> onOnlyOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: const Icon(Icons.lock_open_rounded, size: 16),
              label: const Text('Abiertas'),
              selected: onlyOpen,
              onSelected: onOnlyOpen,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Todos los tipos'),
              selected: kind == null,
              onSelected: (_) => onKind(null),
            ),
          ),
          for (final k in AssignmentKind.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(k.label),
                selected: kind == k,
                onSelected: (_) => onKind(kind == k ? null : k),
              ),
            ),
        ],
      ),
    );
  }
}

/// Panel de una clase: sus tareas, pruebas, exámenes y trabajos.
class TeacherClassAssignmentsScreen extends ConsumerStatefulWidget {
  const TeacherClassAssignmentsScreen({super.key, required this.classId});

  final int classId;

  @override
  ConsumerState<TeacherClassAssignmentsScreen> createState() =>
      _TeacherClassAssignmentsScreenState();
}

class _TeacherClassAssignmentsScreenState
    extends ConsumerState<TeacherClassAssignmentsScreen> {
  AssignmentKind? _kind;
  bool _onlyOpen = false;

  @override
  Widget build(BuildContext context) {
    final cls = _teacherClasses(ref)
        .where((c) => c.classId == widget.classId)
        .firstOrNull;
    return StudentDetailScaffold(
      title: cls?.name ?? 'Clase',
      scrollable: false,
      bottomNav: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _AssignmentsList(
            feed: (
              classId: widget.classId,
              kind: _kind,
              onlyOpen: _onlyOpen,
              search: '',
            ),
            kind: _kind,
            onlyOpen: _onlyOpen,
            onKind: (k) => setState(() => _kind = k),
            onOnlyOpen: (v) => setState(() => _onlyOpen = v),
            canCreate: _canCreate(ref, classId: widget.classId),
            emptyHint: 'Aún no hay tareas en esta clase.',
          ),
        ),
      ),
    );
  }
}

class _AssignmentTile extends StatelessWidget {
  const _AssignmentTile({required this.assignment});

  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AssignmentCard(
        assignment: assignment,
        pastel: true,
        onTap: () => context.push('${Routes.assignments}/${assignment.id}'),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        margin: const EdgeInsets.only(right: 3, bottom: 3),
        decoration: Brutal.decoration(
          context,
          color: selected ? context.buttonFill : palette.cardElevated,
          radius: Radii.md,
          offset: 3,
        ),
        child: Text(
          label,
          style: context.textTheme.labelLarge?.copyWith(
            color: selected ? palette.onAccent : palette.textMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de clase: ícono, nombre, grupo y totales reales de tareas.
class _ClassCard extends StatelessWidget {
  const _ClassCard({
    required this.teacherClass,
    required this.counts,
    required this.loading,
    required this.onTap,
  });

  final TeacherClass teacherClass;
  final ClassAssignmentCounts? counts;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = teacherClass;
    final s = context.pastel(subjectColor(c.name));
    final ink = Brutal.ink(context);
    final total = counts?.total ?? 0;
    final open = counts?.open ?? 0;
    final drafts = counts?.drafts ?? 0;
    final summary = loading
        ? 'Cargando…'
        : total == 0
            ? 'Sin tareas'
            : '$total elemento${total == 1 ? '' : 's'}';

    Widget pill(String text, {bool strong = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: strong ? s.vivid : Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Text(
            text,
            style: context.textTheme.labelSmall?.copyWith(
              color: strong ? Colors.white : s.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BrutalBox(
        onTap: onTap,
        color: s.surface,
        radius: Radii.lg,
        clip: true,
        child: Stack(
          children: [
            Positioned(
              right: -14,
              bottom: -14,
              child: Icon(
                c.icon,
                size: 104,
                color: s.vivid.withValues(alpha: 0.14),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: s.vivid,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: ink, width: Brutal.border),
                    ),
                    child: Icon(c.icon, color: Colors.white, size: 25),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.titleMedium?.copyWith(
                            color: s.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (c.room.isNotEmpty)
                          Text(
                            c.room,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodySmall
                                ?.copyWith(color: s.inkMuted),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            pill(summary, strong: total > 0),
                            if (open > 0)
                              pill('$open abierta${open == 1 ? '' : 's'}'),
                            if (drafts > 0)
                              pill(
                                '$drafts borrador${drafts == 1 ? '' : 'es'}',
                              ),
                            if (!c.isOwner) pill('Colaborativa'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: context.paper,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: ink, width: Brutal.border),
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: context.onPaper,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
