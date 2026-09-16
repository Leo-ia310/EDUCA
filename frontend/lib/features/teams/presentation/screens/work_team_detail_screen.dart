import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/animated_count.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../attendance/data/mock_attendance_data.dart';
import '../../../attendance/domain/entities.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../domain/team_models.dart';
import '../controllers/teams_controller.dart';

class WorkTeamDetailScreen extends ConsumerWidget {
  const WorkTeamDetailScreen({super.key, required this.teamId});
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamByIdProvider(teamId));

    if (team == null) {
      return const StudentDetailScaffold(
        title: 'Equipo',
        bottomNav: false,
        child: EmptyState(
          icon: Icons.groups_2_rounded,
          title: 'Equipo no encontrado',
          subtitle: 'Es posible que se haya eliminado.',
        ),
      );
    }

    final palette = context.palette;
    final classBrief = AttendanceMock.todaysClasses.firstWhere(
      (c) => c.classId == team.classId,
      orElse: () => AttendanceMock.todaysClasses.first,
    );

    return StudentDetailScaffold(
      title: team.name,
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Encabezado con degradado + calificación.
          DepthCard(
            padding: const EdgeInsets.all(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [palette.accent, palette.accentDeep],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${classBrief.subjectName} · ${classBrief.groupName}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Calificación del equipo',
                            style: context.textTheme.labelMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (team.isGraded)
                            AnimatedCount(
                              value: team.score!,
                              suffix:
                                  ' / ${team.maxScore.toStringAsFixed(0)}',
                              style: context.textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          else
                            Text(
                              'Sin calificar',
                              style:
                                  context.textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _gradeSheet(context, ref, team),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: palette.accentDeep,
                        minimumSize: const Size(0, 44),
                      ),
                      icon: const Icon(Icons.star_rounded, size: 18),
                      label: Text(team.isGraded ? 'Ajustar' : 'Calificar'),
                    ),
                  ],
                ),
                if (team.feedback != null && team.feedback!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    team.feedback!,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: Text(
                  'Integrantes (${team.members.length})',
                  style: context.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: () => _addMemberSheet(context, ref, team),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Agregar'),
                style: TextButton.styleFrom(
                  foregroundColor: palette.accentDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (team.members.isEmpty)
            DepthCard(
              soft: true,
              padding: const EdgeInsets.all(16),
              child: Text(
                'Aún no hay integrantes. Usa "Agregar" para asignar alumnos.',
                style: context.textTheme.bodySmall
                    ?.copyWith(color: palette.textMuted),
              ),
            )
          else
            for (final m in team.members)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MemberTile(
                  student: m,
                  onRemove: () => ref
                      .read(teamsControllerProvider.notifier)
                      .removeMember(team.id, m.id),
                ),
              ),

          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _confirmDelete(context, ref, team),
            icon: Icon(Icons.delete_outline_rounded, color: palette.danger),
            label: Text(
              'Eliminar equipo',
              style: TextStyle(color: palette.danger),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addMemberSheet(
    BuildContext context,
    WidgetRef ref,
    WorkTeam team,
  ) async {
    showGlassSheet<void>(
      context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final available = ref.watch(availableStudentsProvider(team.classId));
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Agregar integrantes',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Alumnos de la clase sin equipo asignado.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (available.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'Todos los alumnos ya están asignados.',
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: available.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final s = available[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: UserAvatar(name: s.fullName, size: 38),
                        title: Text(
                          s.fullName,
                          style: Theme.of(ctx).textTheme.titleSmall,
                        ),
                        subtitle:
                            s.studentCode != null ? Text(s.studentCode!) : null,
                        trailing: Icon(
                          Icons.add_circle_outline_rounded,
                          color: context.palette.accentDeep,
                        ),
                        onTap: () => ref
                            .read(teamsControllerProvider.notifier)
                            .addMember(team.id, s),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Listo'),
                ),
              ),
            ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _gradeSheet(
    BuildContext context,
    WidgetRef ref,
    WorkTeam team,
  ) async {
    final scoreCtrl =
        TextEditingController(text: team.score?.toStringAsFixed(0) ?? '');
    final feedbackCtrl = TextEditingController(text: team.feedback ?? '');
    showModalBottomSheet<void>(
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
            Text(
              'Calificar a ${team.name}',
              style: Theme.of(ctx)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'La nota se aplica a los ${team.members.length} integrantes.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: scoreCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText:
                    'Puntaje (max ${team.maxScore.toStringAsFixed(0)})',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: feedbackCtrl,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Comentario (opcional)',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                final n = double.tryParse(scoreCtrl.text);
                if (n == null) return;
                final clamped = n.clamp(0, team.maxScore).toDouble();
                ref.read(teamsControllerProvider.notifier).grade(
                      team.id,
                      score: clamped,
                      feedback: feedbackCtrl.text.trim().isEmpty
                          ? null
                          : feedbackCtrl.text.trim(),
                    );
                Navigator.pop(ctx);
              },
              child: const Text('Guardar nota'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    WorkTeam team,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar equipo'),
        content: Text('¿Eliminar "${team.name}"? Esta acción no se puede '
            'deshacer.',),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      ref.read(teamsControllerProvider.notifier).delete(team.id);
      if (context.mounted) context.pop();
    }
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.student, required this.onRemove});
  final StudentBrief student;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return DepthCard(
      soft: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          UserAvatar(name: student.fullName, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.fullName,
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (student.studentCode != null)
                  Text(student.studentCode!,
                      style: context.textTheme.bodySmall,),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Quitar del equipo',
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded, color: context.palette.textMuted),
          ),
        ],
      ),
    );
  }
}
