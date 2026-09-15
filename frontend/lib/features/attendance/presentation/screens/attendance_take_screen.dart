import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/animated_count.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../data/mock_attendance_data.dart';
import '../../domain/entities.dart';
import '../controllers/attendance_take_controller.dart';
import '../widgets/sync_status_badge.dart';

class AttendanceTakeScreen extends ConsumerStatefulWidget {
  const AttendanceTakeScreen({super.key, required this.classId});
  final int? classId;

  @override
  ConsumerState<AttendanceTakeScreen> createState() =>
      _AttendanceTakeScreenState();
}

class _AttendanceTakeScreenState extends ConsumerState<AttendanceTakeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = widget.classId;
      if (id == null) return;
      final brief = AttendanceMock.todaysClasses.firstWhere(
        (c) => c.classId == id,
        orElse: () => AttendanceMock.todaysClasses.first,
      );
      ref.read(attendanceTakeControllerProvider.notifier).load(brief: brief);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(attendanceTakeControllerProvider);
    final controller = ref.read(attendanceTakeControllerProvider.notifier);
    final brief = state.classBrief;

    if (state.loading && brief == null) {
      return const StudentDetailScaffold(
        title: 'Tomar Asistencia',
        scrollable: false,
        bottomNav: false,
        bodyPadding: EdgeInsets.zero,
        child: SafeArea(bottom: false, child: SkeletonList()),
      );
    }
    if (brief == null) {
      return const StudentDetailScaffold(
        title: 'Tomar Asistencia',
        bottomNav: false,
        child: EmptyState(
          icon: Icons.event_busy_rounded,
          title: 'Sin clase seleccionada',
          subtitle: 'Vuelve atrás y elige una clase.',
        ),
      );
    }

    if (state.finished) {
      return _FinishedSheet(
        brief: brief,
        present: state.present,
        absent: state.absent,
        late: state.late,
        total: state.total,
      );
    }

    return StudentDetailScaffold(
      title: brief.subjectName,
      scrollable: false,
      bottomNav: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _HeaderSummary(
              brief: brief,
              present: state.present,
              absent: state.absent,
              late: state.late,
              total: state.total,
              onMarkAll: controller.markAllPresent,
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: state.rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final row = state.rows[i];
                  return _StudentTile(
                    row: row,
                    onChanged: (status) =>
                        controller.setStatus(row.student.id, status),
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

class _HeaderSummary extends StatelessWidget {
  const _HeaderSummary({
    required this.brief,
    required this.present,
    required this.absent,
    required this.late,
    required this.total,
    required this.onMarkAll,
  });

  final ClassSessionBrief brief;
  final int present;
  final int absent;
  final int late;
  final int total;
  final VoidCallback onMarkAll;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: DepthCard(
        padding: const EdgeInsets.all(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.accent, palette.accentDeep],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${brief.groupName} · ${brief.classroom ?? ''}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${brief.startTime} – ${brief.endTime}',
                        style: context.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SyncStatusBadge(compact: true),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Pill(
                  icon: Icons.check_circle,
                  color: palette.success,
                  label: 'Presentes',
                  value: '$present/$total',
                ),
                const SizedBox(width: 8),
                _Pill(
                  icon: Icons.cancel,
                  color: palette.danger,
                  label: 'Ausentes',
                  value: '$absent',
                ),
                const SizedBox(width: 8),
                _Pill(
                  icon: Icons.schedule,
                  color: palette.warning,
                  label: 'Tarde',
                  value: '$late',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onMarkAll,
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('Todos presentes'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                      minimumSize: const Size(0, 44),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final controller =
                          ref.read(attendanceTakeControllerProvider.notifier);
                      final loading = ref
                          .watch(attendanceTakeControllerProvider)
                          .loading;
                      return FilledButton.icon(
                        onPressed: loading ? null : controller.finishPass,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: palette.accentDeep,
                          minimumSize: const Size(0, 44),
                        ),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(loading ? 'Procesando…' : 'Finalizar pase'),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: context.textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({required this.row, required this.onChanged});
  final AttendanceRow row;
  final ValueChanged<AttendanceStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = _statusColor(row.status, palette);
    return DepthCard(
      soft: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          UserAvatar(name: row.student.fullName, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.student.fullName,
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (row.student.studentCode != null)
                  Text(row.student.studentCode!,
                      style: context.textTheme.bodySmall,),
              ],
            ),
          ),
          if (!row.persisted)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: 'Pendiente de guardar',
                child: Icon(Icons.cloud_off_rounded,
                    size: 14, color: palette.warning,),
              ),
            ),
          PopupMenuButton<AttendanceStatus>(
            position: PopupMenuPosition.under,
            onSelected: onChanged,
            itemBuilder: (_) => [
              for (final s in AttendanceStatus.values)
                PopupMenuItem(
                  value: s,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _statusColor(s, palette),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(s.label),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    row.status.label,
                    style: context.textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, color: color, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(AttendanceStatus s, AppPalette palette) => switch (s) {
        AttendanceStatus.present => palette.success,
        AttendanceStatus.absent => palette.danger,
        AttendanceStatus.late => palette.warning,
        AttendanceStatus.excused => palette.info,
        AttendanceStatus.permission => Colors.deepPurple,
      };
}

class _FinishedSheet extends StatelessWidget {
  const _FinishedSheet({
    required this.brief,
    required this.present,
    required this.absent,
    required this.late,
    required this.total,
  });

  final ClassSessionBrief brief;
  final int present;
  final int absent;
  final int late;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.success.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_circle_rounded,
                      color: palette.success, size: 56,),
                ).animate().scale(
                      duration: 420.ms,
                      curve: Curves.easeOutBack,
                      begin: const Offset(0.6, 0.6),
                      end: const Offset(1, 1),
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pase finalizado',
                textAlign: TextAlign.center,
                style: context.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${brief.subjectName} · ${brief.groupName}',
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              const Center(child: SyncStatusBadge()),
              const SizedBox(height: 24),
              DepthCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _SummaryStat(
                        label: 'Presentes',
                        value: present,
                        color: palette.success,),
                    const SizedBox(width: 8),
                    _SummaryStat(
                        label: 'Ausentes',
                        value: absent,
                        color: palette.danger,),
                    const SizedBox(width: 8),
                    _SummaryStat(
                        label: 'Tarde', value: late, color: palette.warning,),
                    const SizedBox(width: 8),
                    _SummaryStat(
                        label: 'Total', value: total, color: palette.info,),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat(
      {required this.label, required this.value, required this.color,});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          AnimatedCount(
            value: value.toDouble(),
            style: context.textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: context.textTheme.labelSmall),
        ],
      ),
    );
  }
}
