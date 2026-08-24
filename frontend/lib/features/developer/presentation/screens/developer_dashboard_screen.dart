import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/entities.dart';
import '../../providers.dart';

/// Hub del panel de desarrollador: resumen técnico (contadores, tareas
/// pendientes, actividad) + acceso a cada área conectada a `/api/developer/*`.
class DeveloperDashboardScreen extends ConsumerWidget {
  const DeveloperDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final summary = ref.watch(developerSummaryProvider);

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Panel de desarrollador'),
      ),
      child: SafeArea(
        bottom: false,
        child: summary.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateView(message: '$e'),
          data: (data) => RefreshIndicator(
            color: palette.limeDeep,
            onRefresh: () async => ref.invalidate(developerSummaryProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _Hero(counts: data.counts),
                const SizedBox(height: 16),
                const SectionHeader(title: 'Indicadores'),
                const SizedBox(height: 8),
                _StatsGrid(counts: data.counts),
                const SizedBox(height: 20),
                const SectionHeader(title: 'Áreas del panel'),
                const SizedBox(height: 8),
                const _AreasGrid(),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                        child: SectionHeader(title: 'Tareas pendientes'),),
                    Text('${data.pendingTasks.length}',
                        style: context.textTheme.labelLarge?.copyWith(
                          color: palette.textMuted,
                          fontWeight: FontWeight.w800,
                        ),),
                  ],
                ),
                const SizedBox(height: 8),
                if (data.pendingTasks.isEmpty)
                  const EduCard(
                    child: Text('Sin tareas técnicas pendientes.'),
                  )
                else
                  for (final t in data.pendingTasks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TaskTile(task: t),
                    ),
                const SizedBox(height: 16),
                const SectionHeader(title: 'Actividad reciente'),
                const SizedBox(height: 8),
                if (data.recentAuditEvents.isEmpty)
                  const EmptyState(
                    icon: Icons.history_toggle_off_outlined,
                    title: 'Sin actividad',
                    subtitle: 'Los cambios del panel aparecerán aquí.',
                  )
                else
                  EduCard(
                    child: Column(
                      children: [
                        for (var i = 0;
                            i < data.recentAuditEvents.length;
                            i++) ...[
                          if (i > 0)
                            Divider(
                                height: 16,
                                color: Theme.of(context)
                                    .dividerColor
                                    .withValues(alpha: 0.5),),
                          _AuditTile(event: data.recentAuditEvents[i]),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.counts});
  final DevSummaryCounts counts;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EduCard(
      color: palette.cardContrast,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terminal_rounded, color: palette.lime, size: 22),
              const SizedBox(width: 8),
              Text(
                'Resumen técnico',
                style: context.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  value: '${counts.pendingApis}',
                  label: 'APIs por conectar',
                  color: palette.lime,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              Expanded(
                child: _HeroStat(
                  value: '${counts.openTasks}',
                  label: 'Tareas abiertas',
                  color: Colors.white,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              Expanded(
                child: _HeroStat(
                  value: '${counts.failingChecks}',
                  label: 'Checks fallando',
                  color:
                      counts.failingChecks > 0 ? palette.danger : Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat(
      {required this.value, required this.label, required this.color,});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: context.textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.counts});
  final DevSummaryCounts counts;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final stats = <_Stat>[
      _Stat('Instituciones', '${counts.institutions}', Icons.apartment_rounded,
          palette.info,),
      _Stat('Usuarios', '${counts.users}', Icons.people_alt_outlined,
          palette.limeDeep,),
      _Stat(
          'Módulos', '${counts.modules}', Icons.widgets_outlined, palette.info,),
      _Stat('Feature flags', '${counts.featureFlags}', Icons.flag_outlined,
          palette.warning,),
    ];
    return Column(
      children: [
        for (var i = 0; i < stats.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: i + 2 < stats.length ? 10 : 0),
            child: Row(
              children: [
                Expanded(child: _StatCard(stat: stats[i])),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < stats.length
                      ? _StatCard(stat: stats[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat {
  const _Stat(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});
  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    return EduCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: stat.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(stat.icon, color: stat.color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            stat.value,
            style: context.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(stat.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall,),
        ],
      ),
    );
  }
}

/// Las 9 áreas del panel. Cada una se conectará a su pantalla propia en los
/// siguientes incrementos; por ahora las no construidas avisan "próximamente".
class _AreasGrid extends StatelessWidget {
  const _AreasGrid();

  @override
  Widget build(BuildContext context) {
    const areas = <_Area>[
      _Area('apis', 'APIs por conectar', Icons.api_rounded,
          route: Routes.developerApis,),
      _Area('tasks', 'Tareas técnicas', Icons.checklist_rounded,
          route: Routes.developerTasks,),
      _Area('featureFlags', 'Feature flags', Icons.flag_outlined,
          route: Routes.developerFeatureFlags,),
      _Area('systemChecks', 'System checks', Icons.health_and_safety_outlined),
      _Area('modules', 'Módulos', Icons.widgets_outlined),
      _Area('institutions', 'Instituciones', Icons.apartment_rounded),
      _Area('users', 'Usuarios', Icons.people_alt_outlined),
      _Area('audit', 'Auditoría', Icons.receipt_long_outlined),
    ];
    return Column(
      children: [
        for (var i = 0; i < areas.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: i + 2 < areas.length ? 10 : 0),
            child: Row(
              children: [
                Expanded(child: _AreaCard(area: areas[i])),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < areas.length
                      ? _AreaCard(area: areas[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Area {
  const _Area(this.key, this.label, this.icon, {this.route});
  final String key;
  final String label;
  final IconData icon;

  /// Ruta de la pantalla del área; si es `null` aún no está construida.
  final String? route;
}

class _AreaCard extends StatelessWidget {
  const _AreaCard({required this.area});
  final _Area area;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final built = area.route != null;
    return EduCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      onTap: () => built
          ? context.push(area.route!)
          : ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('“${area.label}” — próximamente')),
            ),
      child: Row(
        children: [
          Icon(area.icon,
              color: built ? palette.limeDeep : palette.textMuted, size: 22,),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              area.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: palette.textMuted, size: 20),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final DevTask task;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (statusColor, statusLabel) = _taskStatus(task.status, palette);
    return EduCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              _Pill(label: statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (task.priority != null)
                _MetaText(
                  icon: Icons.flag_outlined,
                  text: _priorityLabel(task.priority!),
                  color: _priorityColor(task.priority!, palette),
                ),
              if (task.moduleKey != null)
                _MetaText(icon: Icons.widgets_outlined, text: task.moduleKey!),
              if (task.frontendRequired)
                const _MetaText(icon: Icons.phone_iphone_rounded, text: 'Frontend'),
              _MetaText(
                icon: task.backendReady
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                text: task.backendReady ? 'Backend listo' : 'Backend pendiente',
                color: task.backendReady ? palette.success : palette.textMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.event});
  final DevAuditEvent event;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (icon, color) = _auditVisual(event.action, palette);
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_actionLabel(event.action)} · ${_tableLabel(event.entityTable)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                _relative(event.createdAt),
                style: context.textTheme.labelSmall
                    ?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 3),
        Text(text,
            style: context.textTheme.labelSmall
                ?.copyWith(color: c, fontWeight: FontWeight.w600),),
      ],
    );
  }
}

(Color, String) _taskStatus(String status, AppPalette palette) {
  return switch (status) {
    'in_progress' => (palette.info, 'En progreso'),
    'ready' => (palette.limeDeep, 'Listo'),
    'blocked' => (palette.danger, 'Bloqueado'),
    'done' => (palette.success, 'Hecho'),
    'cancelled' => (palette.textMuted, 'Cancelado'),
    _ => (palette.warning, 'Pendiente'),
  };
}

String _priorityLabel(String p) => switch (p) {
      'critical' => 'Crítica',
      'high' => 'Alta',
      'medium' => 'Media',
      _ => 'Baja',
    };

Color _priorityColor(String p, AppPalette palette) => switch (p) {
      'critical' => palette.danger,
      'high' => palette.warning,
      'medium' => palette.info,
      _ => palette.textMuted,
    };

(IconData, Color) _auditVisual(String action, AppPalette palette) {
  return switch (action) {
    'create' => (Icons.add_circle_outline, palette.success),
    'update' => (Icons.edit_outlined, palette.info),
    'archive' => (Icons.archive_outlined, palette.danger),
    _ => (Icons.bolt_outlined, palette.textMuted),
  };
}

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
  return DateFormat('d MMM, HH:mm', 'es').format(d);
}
