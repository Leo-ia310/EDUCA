import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
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

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Tomar Asistencia'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: IconButton(
              icon: const Icon(Icons.history_rounded),
              tooltip: 'Historial',
              onPressed: () => context.push(Routes.attendanceHistory),
            ),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
                ],
              ),
            ),
            Expanded(
              child: classes.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (list) {
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.event_busy_outlined,
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
    return EduCard(
      onTap: () => context.push(
        '${Routes.attendanceTake}?classId=${brief.classId}',
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: palette.limeSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              brief.startTime,
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: palette.limeDeep,
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
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
