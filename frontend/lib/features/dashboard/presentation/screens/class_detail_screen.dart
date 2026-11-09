import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/utils/plural.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../collaborations/class_students_screen.dart';
import '../../../collaborations/providers.dart';
import '../../data/class_insights.dart';
import '../../data/mock_dashboard_data.dart';
import '../widgets/student_chrome.dart';

const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _weekdaysLong = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

/// Detalle de una clase del maestro. Destino del container-transform desde la
/// tarjeta de clase del dashboard.
class ClassDetailScreen extends ConsumerWidget {
  const ClassDetailScreen({super.key, required this.teacherClass});
  final TeacherClass teacherClass;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classId = teacherClass.classId;
    final insights =
        classId == null ? null : ref.watch(classInsightsProvider(classId));
    final data = insights?.valueOrNull;
    final loading = insights?.isLoading ?? false;

    // Quién invitó al docente a esta clase colaborativa.
    String? inviter;
    if (!teacherClass.isOwner && classId != null) {
      final invitations = ref
              .watch(collaborationWorkspaceProvider)
              .valueOrNull?['invitations'] as List? ??
          const [];
      for (final i in invitations) {
        if (i is Map &&
            i['classId'] == classId &&
            i['incoming'] == true &&
            i['status'] == 'active') {
          inviter = i['inviterName'] as String?;
          break;
        }
      }
    }

    final accent = subjectColor(teacherClass.name);
    final ink = subjectInk(teacherClass.name);
    final room = data?.slots
        .map((s) => s.room)
        .firstWhere((r) => r != null && r.isNotEmpty, orElse: () => null);

    return StudentDetailScaffold(
      title: teacherClass.name,
      bottomNav: false,
      onRefresh: classId == null
          ? null
          : () async {
              ref.invalidate(classInsightsProvider(classId));
              await ref.read(classInsightsProvider(classId).future);
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(
            teacherClass: teacherClass,
            inviter: inviter,
            room: room,
          ),
          const SizedBox(height: 16),
          if (classId != null) ...[
            _Stats(data: data, loading: loading),
            if ((data?.atRiskCount ?? 0) > 0) ...[
              const SizedBox(height: 12),
              _AttentionBanner(
                count: data!.atRiskCount,
                onTap: () => _openStudents(context),
              ),
            ],
            const SizedBox(height: 20),
            _ScheduleCard(slots: data?.slots, loading: loading),
          ],
          if (!teacherClass.isOwner && teacherClass.permissions != null) ...[
            const SizedBox(height: 20),
            _PermissionsCard(permissions: teacherClass.permissions!),
          ],
          const SizedBox(height: 20),
          const _SectionTitle(icon: Icons.bolt_rounded, text: 'Acciones'),
          const SizedBox(height: 10),
          if (teacherClass.isOwner) ...[
            _Action(
              icon: Icons.group_add_rounded,
              label: 'Invitar profesor colaborador',
              subtitle: 'Comparte esta clase con otro docente',
              accent: accent,
              ink: ink,
              onTap: () => context.push(Routes.collaborations),
            ),
            const SizedBox(height: 12),
          ],
          if (teacherClass.can('students.view') && classId != null) ...[
            _Action(
              icon: Icons.groups_rounded,
              label: 'Ver estudiantes',
              subtitle: data == null
                  ? 'Asistencia y promedio de cada uno'
                  : '${plural(data.students.length, 'estudiante')} · asistencia y promedio',
              accent: accent,
              ink: ink,
              onTap: () => _openStudents(context),
            ),
            const SizedBox(height: 12),
          ],
          if (teacherClass.can('attendance.write')) ...[
            _Action(
              icon: Icons.how_to_reg_rounded,
              label: 'Tomar asistencia',
              subtitle: 'Pasa lista de esta clase hoy',
              accent: accent,
              ink: ink,
              onTap: () => context.push(
                classId == null
                    ? Routes.attendance
                    : '${Routes.attendanceTake}?classId=$classId',
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (teacherClass.can('students.view')) ...[
            _Action(
              icon: Icons.grid_view_rounded,
              label: 'Libro de notas',
              subtitle: (data?.pendingGrading ?? 0) > 0
                  ? '${plural(data!.pendingGrading!, 'entrega')} por calificar'
                  : 'Notas por evaluación y periodo',
              accent: accent,
              ink: ink,
              onTap: () => context.push(Routes.gradebook),
            ),
            const SizedBox(height: 12),
          ],
          _Action(
            icon: Icons.assignment_rounded,
            label: 'Tareas y exámenes',
            subtitle: (data?.activeAssignments ?? 0) > 0
                ? '${plural(data!.activeAssignments!, 'activa')} · ver y crear'
                : 'Crea y revisa tareas y exámenes',
            accent: accent,
            ink: ink,
            onTap: () => context.push(Routes.assignments),
          ),
        ],
      ),
    );
  }

  void _openStudents(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClassStudentsScreen(
          classId: teacherClass.classId!,
          className: '${teacherClass.name} · ${teacherClass.room}',
        ),
      ),
    );
  }
}

/// Portada de la clase: materia, si es propia o colaborativa, salón y aula.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.teacherClass,
    required this.inviter,
    required this.room,
  });
  final TeacherClass teacherClass;
  final String? inviter;
  final String? room;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subjectColor(teacherClass.name));
    final ink = Brutal.ink(context);
    final palette = context.palette;
    final owner = teacherClass.isOwner;
    return BrutalBox(
      color: s.surface,
      radius: Radii.lg,
      clip: true,
      child: Stack(
        children: [
          Positioned(
            right: -18,
            bottom: -18,
            child: Icon(
              teacherClass.icon,
              size: 140,
              color: s.vivid.withValues(alpha: 0.16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: s.vivid,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(color: ink, width: Brutal.border),
                      ),
                      child: Icon(
                        teacherClass.icon,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _RoleChip(owner: owner),
                          const SizedBox(height: 6),
                          Text(
                            teacherClass.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.titleLarge?.copyWith(
                              color: s.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _HeroMeta(
                      icon: Icons.groups_rounded,
                      text: teacherClass.room,
                      color: s.inkMuted,
                    ),
                    if (room != null && room!.isNotEmpty)
                      _HeroMeta(
                        icon: Icons.meeting_room_rounded,
                        text: room!,
                        color: s.inkMuted,
                      ),
                    if (!owner && inviter != null && inviter!.isNotEmpty)
                      _HeroMeta(
                        icon: Icons.person_add_alt_1_rounded,
                        text: 'Invitada por $inviter',
                        color: s.inkMuted,
                      ),
                  ],
                ),
                if (!owner) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Eres colaborador: solo puedes hacer lo que el titular te permitió.',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «Propia» o «Colaborativa», reconocible de un vistazo.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.owner});
  final bool owner;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bg = owner ? palette.accentDeep : Colors.white;
    final fg = owner ? Colors.white : palette.accentDeep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            size: 15,
            color: fg,
          ),
          const SizedBox(width: 5),
          Text(
            owner ? 'Clase propia' : 'Clase colaborativa',
            style: context.textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: context.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Cuatro cifras de la clase: estudiantes, asistencia, promedio y por calificar.
class _Stats extends StatelessWidget {
  const _Stats({required this.data, required this.loading});
  final ClassInsights? data;
  final bool loading;

  String _v(String? value) => loading ? '…' : (value ?? '—');

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final rate = data?.attendanceRate;
    final avg = data?.gradeAverage;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.groups_rounded,
                color: palette.info,
                value: _v(data == null ? null : '${data!.students.length}'),
                label: 'Estudiantes',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                icon: Icons.how_to_reg_rounded,
                color: palette.success,
                value: _v(rate == null ? null : '${(rate * 100).round()}%'),
                label: 'Asistencia',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.grade_rounded,
                color: palette.warning,
                value: _v(avg == null ? null : '${avg.round()}'),
                label: 'Promedio',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                icon: Icons.rate_review_rounded,
                color: palette.danger,
                value: _v(
                  data?.pendingGrading == null
                      ? null
                      : '${data!.pendingGrading}',
                ),
                label: 'Por calificar',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return BrutalBox(
      color: context.paper,
      radius: Radii.lg,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: context.onPaper,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.palette.textMuted,
                    fontWeight: FontWeight.w700,
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

class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.danger.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: palette.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 estudiante necesita atención (asistencia o notas bajas)'
                      : '$count estudiantes necesitan atención (asistencia o notas bajas)',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: palette.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.danger),
            ],
          ),
        ),
      ),
    );
  }
}

/// Próxima clase y horario semanal.
class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.slots, required this.loading});
  final List<ClassWeekSlot>? slots;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final next = slots == null ? null : nextClassSlot(slots!, DateTime.now());
    String when(int ahead, int weekday) => ahead == 0
        ? 'Hoy'
        : ahead == 1
            ? 'Mañana'
            : _weekdaysLong[weekday][0].toUpperCase() +
                _weekdaysLong[weekday].substring(1);

    return BrutalBox(
      color: context.paper,
      radius: Radii.lg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(icon: Icons.schedule_rounded, text: 'Horario'),
          const SizedBox(height: 12),
          if (loading && slots == null)
            Text(
              'Cargando horario…',
              style: context.textTheme.bodySmall
                  ?.copyWith(color: palette.textMuted),
            )
          else if (slots == null || slots!.isEmpty)
            Text(
              'Esta clase todavía no tiene horario asignado.',
              style: context.textTheme.bodySmall
                  ?.copyWith(color: palette.textMuted),
            )
          else ...[
            if (next != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_available_rounded,
                      color: palette.accentDeep,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Próxima clase: ${when(next.daysAhead, next.slot.weekdayIndex)} '
                        '${next.slot.start}${next.slot.end.isEmpty ? '' : ' – ${next.slot.end}'}',
                        style: context.textTheme.titleSmall?.copyWith(
                          color: palette.accentDeep,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            for (final slot in slots!)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: palette.accentDeep,
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child: Text(
                        _weekdays[slot.weekdayIndex.clamp(0, 6)],
                        style: context.textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${slot.start}${slot.end.isEmpty ? '' : ' – ${slot.end}'}',
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.onPaper,
                        ),
                      ),
                    ),
                    if (slot.room != null && slot.room!.isNotEmpty) ...[
                      Icon(
                        Icons.meeting_room_rounded,
                        size: 16,
                        color: palette.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        slot.room!,
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: palette.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Qué puede hacer el colaborador en esta clase.
class _PermissionsCard extends StatelessWidget {
  const _PermissionsCard({required this.permissions});
  final Set<String> permissions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final labels = [
      for (final entry in collaborationPermissions.entries)
        if (entry.key != 'class.view' && permissions.contains(entry.key))
          entry.value,
    ];
    return BrutalBox(
      color: context.paper,
      radius: Radii.lg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.verified_user_rounded,
            text: 'Tus permisos en esta clase',
          ),
          const SizedBox(height: 12),
          if (labels.isEmpty)
            Text(
              'Solo puedes ver la clase.',
              style: context.textTheme.bodySmall
                  ?.copyWith(color: palette.textMuted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in labels)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: palette.success.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 15,
                          color: palette.success,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: context.textTheme.labelMedium?.copyWith(
                            color: palette.success,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.palette.accentDeep),
        const SizedBox(width: 8),
        Text(
          text,
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.accent,
    required this.ink,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Color accent;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return BrutalBox(
      onTap: onTap,
      color: context.paper,
      radius: Radii.lg,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(icon, color: ink, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: context.onPaper,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: palette.textMuted),
        ],
      ),
    );
  }
}
