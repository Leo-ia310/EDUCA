import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../domain/entities.dart';
import '../../providers.dart';

/// Área "Auditoría" (solo lectura): actividad técnica del panel sobre
/// `/api/developer/audit-events`.
class DeveloperAuditScreen extends ConsumerWidget {
  const DeveloperAuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final async = ref.watch(developerAuditEventsProvider);

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Auditoría'),
      ),
      child: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateView(message: '$e'),
          data: (events) => RefreshIndicator(
            color: palette.limeDeep,
            onRefresh: () async =>
                ref.invalidate(developerAuditEventsProvider),
            child: events.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: const [
                      EmptyState(
                        icon: Icons.history_toggle_off_outlined,
                        title: 'Sin actividad',
                        subtitle: 'Los cambios del panel aparecerán aquí.',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _AuditCard(event: events[i]),
                  ),
          ),
        ),
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.event});
  final DevAuditEvent event;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (icon, color) = _visual(event.action, palette);
    return EduCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_actionLabel(event.action)} · ${_tableLabel(event.entityTable)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (event.entityId != null) '#${event.entityId}',
                    if (event.actorUserId != null)
                      'actor ${event.actorUserId}',
                    _relative(event.createdAt),
                  ].join(' · '),
                  style: context.textTheme.labelSmall
                      ?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

(IconData, Color) _visual(String action, AppPalette palette) => switch (action) {
      'create' => (Icons.add_circle_outline, palette.success),
      'update' => (Icons.edit_outlined, palette.info),
      'archive' => (Icons.archive_outlined, palette.danger),
      _ => (Icons.bolt_outlined, palette.textMuted),
    };

String _actionLabel(String action) => switch (action) {
      'create' => 'Creación',
      'update' => 'Actualización',
      'archive' => 'Archivado',
      _ => action,
    };

String _tableLabel(String table) => switch (table) {
      'developer_dashboard_modules' => 'Módulo',
      'developer_api_registry' => 'API',
      'developer_tasks' => 'Tarea',
      'developer_feature_flags' => 'Feature flag',
      'developer_system_checks' => 'System check',
      _ => table,
    };

String _relative(DateTime? d) {
  if (d == null) return '—';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays < 30) return 'hace ${diff.inDays} d';
  return DateFormat('d MMM, HH:mm', 'es').format(d);
}
