import 'package:go_router/go_router.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/network/provider_cache.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/entrance.dart';
import '../../../../core/widgets/open_card.dart';
import '../../../collaborations/providers.dart';
import '../../data/mock_dashboard_data.dart';
import '../../providers.dart';
import '../widgets/student_chrome.dart';
import 'class_detail_screen.dart';

/// Panel "Mis clases" del docente: las clases propias y, aparte, las
/// colaborativas (de otros docentes que lo invitaron).
class TeacherClassesScreen extends ConsumerWidget {
  const TeacherClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(teacherDashboardProvider);
    final classes = result.scopedValue?.myClasses ?? <TeacherClass>[];

    // Quién invitó al docente a cada clase colaborativa.
    final invitations = ref
            .watch(collaborationWorkspaceProvider)
            .valueOrNull?['invitations'] as List? ??
        const [];
    final inviters = <int, String>{
      for (final i in invitations)
        if (i is Map &&
            i['incoming'] == true &&
            i['status'] == 'active' &&
            i['classId'] is num &&
            i['inviterName'] is String)
          (i['classId'] as num).toInt(): i['inviterName'] as String,
    };

    final own = [
      for (final c in classes)
        if (c.isOwner) c,
    ];
    final shared = [
      for (final c in classes)
        if (!c.isOwner) c,
    ];

    return StudentDetailScaffold(
      title: 'Mis clases',
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      onRefresh: () async {
        ref.invalidate(teacherDashboardProvider);
        ref.invalidate(collaborationWorkspaceProvider);
        await ref.read(teacherDashboardProvider.future);
      },
      fab: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.collaborations),
        icon: const Icon(Icons.group_add_rounded),
        label: const Text('Colaboradores'),
      ),
      child: SafeArea(
        bottom: false,
        child: result.isLoading && !result.isRefreshing
            ? const SkeletonList()
            : result.hasError
                ? ErrorStateView(
                    message: 'No se pudieron cargar tus clases.',
                    onRetry: () => ref.invalidate(teacherDashboardProvider),
                  )
                : classes.isEmpty
                    ? const EmptyState(
                        icon: Icons.class_rounded,
                        title: 'Sin clases asignadas',
                        subtitle:
                            'Aquí aparecerán tus clases propias y las colaboraciones aceptadas.',
                      )
                    : ListView(
                        // Espacio inferior para que el botón flotante no tape la última tarjeta.
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 110),
                        children: [
                          if (own.isNotEmpty)
                            ..._section(
                              context,
                              title: 'Mis clases',
                              icon: Icons.workspace_premium_rounded,
                              classes: own,
                              inviters: inviters,
                              firstIndex: 0,
                            ),
                          if (shared.isNotEmpty)
                            ..._section(
                              context,
                              title: 'Colaborativas',
                              icon: Icons.group_rounded,
                              hint:
                                  'Clases de otros docentes que te invitaron a colaborar.',
                              classes: shared,
                              inviters: inviters,
                              firstIndex: own.length,
                            ),
                        ],
                      ),
      ),
    );
  }

  List<Widget> _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<TeacherClass> classes,
    required Map<int, String> inviters,
    required int firstIndex,
    String? hint,
  }) {
    final palette = context.palette;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 0, 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: palette.accentDeep),
            const SizedBox(width: 8),
            Text(
              title,
              style: context.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: palette.accentSoft,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                '${classes.length}',
                style: context.textTheme.labelSmall?.copyWith(
                  color: palette.accentDeep,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
      if (hint != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
          child: Text(
            hint,
            style:
                context.textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ),
      for (final (i, c) in classes.indexed)
        entranceItem(
          context,
          firstIndex + i,
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OpenCard(
              borderRadius: Radii.lg,
              open: (context) => ClassDetailScreen(teacherClass: c),
              closed: (context, open) => _ClassTile(
                teacherClass: c,
                inviter: c.classId == null ? null : inviters[c.classId],
                onTap: open,
              ),
            ),
          ),
        ),
      const SizedBox(height: 8),
    ];
  }
}

class _ClassTile extends StatelessWidget {
  const _ClassTile({
    required this.teacherClass,
    required this.inviter,
    required this.onTap,
  });

  final TeacherClass teacherClass;
  final String? inviter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subjectColor(teacherClass.name));
    final ink = Brutal.ink(context);
    final palette = context.palette;
    final owner = teacherClass.isOwner;
    // La colaborativa se distingue a primera vista: fondo blanco con una franja
    // del color de la materia a la izquierda y la etiqueta «Colaborativa».
    final surface = owner ? s.surface : context.paper;
    final textInk = owner ? s.ink : context.onPaper;
    final muted = owner ? s.inkMuted : palette.textMuted;

    return BrutalBox(
      onTap: onTap,
      color: surface,
      radius: Radii.lg,
      clip: true,
      child: Stack(
        children: [
          if (!owner)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 8, color: s.vivid),
            ),
          Positioned(
            right: -14,
            bottom: -14,
            child: Icon(
              teacherClass.icon,
              size: 110,
              color: s.vivid.withValues(alpha: owner ? 0.16 : 0.1),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(owner ? 16 : 22, 16, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: s.vivid,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: ink, width: Brutal.border),
                  ),
                  child: Icon(teacherClass.icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        teacherClass.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleMedium?.copyWith(
                          color: textInk,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _RoleChip(owner: owner),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.groups_rounded, size: 15, color: muted),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              teacherClass.room,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.bodySmall
                                  ?.copyWith(color: muted),
                            ),
                          ),
                        ],
                      ),
                      if (!owner && inviter != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_add_alt_1_rounded,
                                size: 15,
                                color: muted,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  'Invitada por $inviter',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textTheme.bodySmall
                                      ?.copyWith(color: muted),
                                ),
                              ),
                            ],
                          ),
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
    );
  }
}

/// «Propia» (relleno) o «Colaborativa» (contorno) con su ícono.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.owner});
  final bool owner;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bg = owner ? palette.accentDeep : Colors.transparent;
    final fg = owner ? Colors.white : palette.accentDeep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.pill),
        border:
            owner ? null : Border.all(color: palette.accentDeep, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            owner ? Icons.workspace_premium_rounded : Icons.group_rounded,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            owner ? 'Clase propia' : 'Clase colaborativa',
            style: context.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
