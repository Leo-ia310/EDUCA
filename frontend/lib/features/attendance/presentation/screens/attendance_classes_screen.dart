import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/utils/plural.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../dashboard/data/supabase_dashboard_datasource.dart'
    show iconForSubject;
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../domain/entities.dart';
import '../controllers/attendance_take_controller.dart'
    show todaysClassesProvider;
import '../widgets/sync_status_badge.dart';

/// Pantalla intermedia: el docente elige la clase a la que va a pasar lista.
class AttendanceClassesScreen extends ConsumerWidget {
  const AttendanceClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(todaysClassesProvider);

    return StudentDetailScaffold(
      title: 'Tomar Asistencia',
      scrollable: false,
      bottomNav: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 20, 0),
              child: _TodayHeader(briefs: classes.asData?.value),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 20, 0),
              child: _HistoryEntry(
                onTap: () => context.push(Routes.attendanceHistory),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: classes.when(
                loading: () => const SkeletonList(),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (list) {
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.event_busy_rounded,
                      title: 'Sin clases hoy',
                      subtitle: 'No tienes clases programadas para hoy.',
                    );
                  }
                  final today = list.where((b) => b.scheduledToday).toList();
                  final others = list.where((b) => !b.scheduledToday).toList();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 20, 28),
                    children: [
                      if (today.isNotEmpty)
                        ..._section(
                          context,
                          title: 'Clases de hoy',
                          icon: Icons.today_rounded,
                          briefs: today,
                        ),
                      if (others.isNotEmpty)
                        ..._section(
                          context,
                          title: today.isEmpty ? 'Tus clases' : 'Otras clases',
                          icon: Icons.menu_book_rounded,
                          briefs: others,
                          hint: today.isEmpty
                              ? 'Hoy no tienes clases en tu horario; puedes pasar lista a cualquiera.'
                              : 'No están en tu horario de hoy, pero puedes pasar lista.',
                        ),
                    ],
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

List<Widget> _section(
  BuildContext context, {
  required String title,
  required IconData icon,
  required List<ClassSessionBrief> briefs,
  String? hint,
}) {
  final palette = context.palette;
  return [
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 0, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: palette.accentDeep),
          const SizedBox(width: 8),
          Text(
            title,
            style: context.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Text(
              '${briefs.length}',
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
          style: context.textTheme.bodySmall?.copyWith(
            color: palette.textMuted,
          ),
        ),
      ),
    for (var i = 0; i < briefs.length; i++) ...[
      if (i > 0) const SizedBox(height: 14),
      _ClassCard(brief: briefs[i]),
    ],
  ];
}

/// Resumen del día: título, fecha, cuántas clases/estudiantes y estado de envío.
class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.briefs});
  final List<ClassSessionBrief>? briefs;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final now = DateTime.now();
    final raw = DateFormat("EEEE d 'de' MMMM", 'es').format(now);
    final date = raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);
    final today = briefs?.where((b) => b.scheduledToday).toList();
    final students = today?.fold<int>(0, (sum, b) => sum + b.studentCount) ?? 0;

    return BrutalBox(
      radius: Radii.lg,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [palette.accent, palette.accentDeep],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: const Icon(
                  Icons.fact_check_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pase de lista',
                      style: context.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      date,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const SyncStatusBadge(compact: true, onDark: true),
            ],
          ),
          if (briefs != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeaderChip(
                  icon: Icons.event_note_rounded,
                  text: today!.isEmpty
                      ? 'Sin clases en tu horario hoy'
                      : '${plural(today.length, 'clase')} hoy',
                ),
                if (students > 0)
                  _HeaderChip(
                    icon: Icons.groups_rounded,
                    text: plural(students, 'estudiante'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: context.textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Acceso al historial como una tarjeta con su propia explicación.
class _HistoryEntry extends StatelessWidget {
  const _HistoryEntry({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return BrutalBox(
      onTap: onTap,
      color: context.paper,
      radius: Radii.lg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(
              Icons.history_rounded,
              color: palette.accentDeep,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Historial de asistencia',
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: context.onPaper,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pases anteriores y su estado de envío',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: palette.textMuted,
                  ),
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

class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.brief});
  final ClassSessionBrief brief;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subjectColor(brief.subjectName));
    final ink = Brutal.ink(context);
    final icon = iconForSubject(brief.subjectName);
    final room = brief.classroom?.trim();

    return BrutalBox(
      onTap: () => context.push(
        '${Routes.attendanceTake}?classId=${brief.classId}',
      ),
      color: s.surface,
      radius: Radii.lg,
      clip: true,
      child: Stack(
        children: [
          Positioned(
            right: -14,
            bottom: -14,
            child:
                Icon(icon, size: 104, color: s.vivid.withValues(alpha: 0.16)),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
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
                  child: Icon(icon, color: Colors.white, size: 27),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        brief.subjectName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleMedium?.copyWith(
                          color: s.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          if (brief.startTime.isNotEmpty)
                            _Meta(
                              icon: Icons.schedule_rounded,
                              text: '${brief.startTime} – ${brief.endTime}',
                              color: s.ink,
                              strong: true,
                            ),
                          _Meta(
                            icon: Icons.groups_rounded,
                            text: brief.groupName,
                            color: s.inkMuted,
                          ),
                          if (room != null && room.isNotEmpty)
                            _Meta(
                              icon: Icons.meeting_room_rounded,
                              text: room,
                              color: s.inkMuted,
                            ),
                          _Meta(
                            icon: Icons.people_alt_rounded,
                            text: plural(brief.studentCount, 'estudiante'),
                            color: s.inkMuted,
                          ),
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
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.icon,
    required this.text,
    required this.color,
    this.strong = false,
  });
  final IconData icon;
  final String text;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: context.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
