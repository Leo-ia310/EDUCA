import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../domain/entities.dart';
import '../controllers/attendance_take_controller.dart' show todaysClassesProvider;
import '../widgets/sync_status_badge.dart';

/// Pantalla intermedia: el docente elige la clase a la que va a pasar lista.
class AttendanceClassesScreen extends ConsumerWidget {
  const AttendanceClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(todaysClassesProvider);
    final palette = context.palette;

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
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Selecciona una clase de hoy',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                  const SyncStatusBadge(compact: true),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => context.push(Routes.attendanceHistory),
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('Historial'),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.accentDeep,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
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
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _ClassCard(brief: list[i]),
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

class _ClassCard extends ConsumerWidget {
  const _ClassCard({required this.brief});
  final ClassSessionBrief brief;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return DepthCard(
      soft: true,
      padding: const EdgeInsets.all(16),
      onTap: () => context.push(
        '${Routes.attendanceTake}?classId=${brief.classId}',
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            alignment: Alignment.center,
            child: Text(
              brief.startTime,
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: palette.accentDeep,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  brief.subjectName,
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${brief.groupName} · ${brief.classroom ?? '—'}',
                  style: context.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  '${brief.studentCount} estudiantes',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w700,
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
