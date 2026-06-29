import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/attendance_sync_service.dart';
import '../../domain/entities.dart';
import '../../providers.dart';
import '../widgets/sync_status_badge.dart';

final _historyProvider = FutureProvider.autoDispose<List<AttendanceSessionSummary>>(
  (ref) => ref.watch(attendanceRepositoryProvider).sessionsHistory(),
);

class AttendanceHistoryScreen extends ConsumerWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(_historyProvider);
    final palette = context.palette;

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Historial de Asistencia'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: SyncStatusBadge(compact: true)),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _SyncControls(),
            ),
            Expanded(
              child: history.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (list) {
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.fact_check_outlined,
                      title: 'Sin pases registrados',
                      subtitle:
                          'Cuando finalices un pase de asistencia, lo verás aquí.',
                    );
                  }
                  return RefreshIndicator(
                    color: palette.limeDeep,
                    onRefresh: () async => ref.invalidate(_historyProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _SessionTile(summary: list[i]),
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

class _SyncControls extends ConsumerWidget {
  const _SyncControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(attendanceSyncProvider);
    final service = ref.read(attendanceSyncProvider.notifier);
    final palette = context.palette;

    return EduCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: palette.limeSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.cloud_sync_outlined,
                color: palette.limeDeep, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.pending == 0
                      ? 'Todo al día'
                      : '${status.pending} pendientes',
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (status.lastSyncAt != null)
                  Text(
                    'Última sincronización: ${DateFormat('HH:mm').format(status.lastSyncAt!)}',
                    style: context.textTheme.bodySmall,
                  )
                else
                  Text('Sin sincronizar todavía',
                      style: context.textTheme.bodySmall),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: status.syncing ? null : service.processQueue,
            style: FilledButton.styleFrom(
              backgroundColor: palette.limeDeep,
              foregroundColor: const Color(0xFF1E2218),
              minimumSize: const Size(0, 40),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child:
                Text(status.syncing ? 'Sincronizando…' : 'Sincronizar ahora'),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.summary});
  final AttendanceSessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fmt = DateFormat("EEE d MMM, HH:mm", 'es');
    return EduCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  summary.subjectName,
                  style: context.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (summary.pendingSync > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: palette.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${summary.pendingSync} pendiente${summary.pendingSync == 1 ? '' : 's'}',
                    style: context.textTheme.labelSmall?.copyWith(
                      color: palette.warning,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${summary.groupName} · ${fmt.format(summary.date)}',
            style: context.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Counter(
                color: palette.success,
                label: 'Presentes',
                value: summary.present,
              ),
              _Counter(
                color: palette.danger,
                label: 'Ausentes',
                value: summary.absent,
              ),
              _Counter(
                color: palette.warning,
                label: 'Tarde',
                value: summary.late,
              ),
              _Counter(
                color: palette.info,
                label: 'Total',
                value: summary.totalStudents,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.color,
    required this.label,
    required this.value,
  });
  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: context.textTheme.titleMedium?.copyWith(
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
