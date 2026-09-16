import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/educa_fab.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../attendance/data/mock_attendance_data.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../domain/team_models.dart';
import '../controllers/teams_controller.dart';

class WorkTeamsScreen extends ConsumerStatefulWidget {
  const WorkTeamsScreen({super.key});

  @override
  ConsumerState<WorkTeamsScreen> createState() => _WorkTeamsScreenState();
}

class _WorkTeamsScreenState extends ConsumerState<WorkTeamsScreen> {
  int _classId = 101;

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(teamsForClassProvider(_classId));

    return StudentDetailScaffold(
      title: 'Equipos de trabajo',
      scrollable: false,
      bottomNav: false,
      bodyPadding: EdgeInsets.zero,
      fab: EducaFab(onPressed: _createTeam),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: DepthCard(
                soft: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.groups_2_rounded,
                        color: context.palette.accentDeep, size: 20,),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<int>(
                        value: _classId,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final c in AttendanceMock.todaysClasses)
                            DropdownMenuItem(
                              value: c.classId,
                              child: Text(
                                '${c.subjectName} · ${c.groupName}',
                                overflow: TextOverflow.ellipsis,
                                style: context.textTheme.titleSmall,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _classId = v);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: teams.isEmpty
                  ? EmptyState(
                      icon: Icons.groups_2_rounded,
                      title: 'Sin equipos',
                      subtitle:
                          'Crea el primer equipo de esta clase con el botón +.',
                      actionLabel: 'Nuevo equipo',
                      onAction: _createTeam,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      itemCount: teams.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _TeamCard(
                        team: teams[i],
                        onTap: () => context.push(
                          '${Routes.workTeams}/${teams[i].id}',
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createTeam() async {
    final ctrl = TextEditingController();
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassSurface(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Nuevo equipo',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre del equipo'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final team =
        ref.read(teamsControllerProvider.notifier).create(
              classId: _classId,
              name: name,
            );
    if (!mounted) return;
    // Abre el detalle para agregar integrantes de una vez.
    context.push('${Routes.workTeams}/${team.id}');
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.team, required this.onTap});
  final WorkTeam team;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DepthCard(
      soft: true,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  team.name,
                  style: context.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _GradeChip(team: team),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MemberAvatars(members: team.members),
              const SizedBox(width: 10),
              Text(
                '${team.members.length} integrante'
                '${team.members.length == 1 ? '' : 's'}',
                style: context.textTheme.bodySmall
                    ?.copyWith(color: palette.textMuted),
              ),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, color: palette.textMuted),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pila de avatares superpuestos (hasta 4 + contador).
class _MemberAvatars extends StatelessWidget {
  const _MemberAvatars({required this.members});
  final List<dynamic> members;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Text(
        'Sin integrantes',
        style: context.textTheme.bodySmall
            ?.copyWith(color: context.palette.textMuted),
      );
    }
    const max = 4;
    final shown = members.take(max).toList();
    final extra = members.length - shown.length;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      height: 32,
      width: shown.length * 22.0 + 10 + (extra > 0 ? 22 : 0),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 22.0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: UserAvatar(name: shown[i].fullName as String, size: 28),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * 22.0,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.palette.accentSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: bg, width: 2),
                ),
                child: Text(
                  '+$extra',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.palette.accentDeep,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GradeChip extends StatelessWidget {
  const _GradeChip({required this.team});
  final WorkTeam team;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final graded = team.isGraded;
    final color = graded ? palette.success : palette.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        graded
            ? '${team.score!.toStringAsFixed(0)} / ${team.maxScore.toStringAsFixed(0)}'
            : 'Sin calificar',
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
