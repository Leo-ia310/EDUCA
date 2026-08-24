import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../domain/entities.dart';
import '../../providers.dart';

/// Área "APIs por conectar": inventario filtrable de los endpoints del backend
/// (`GET /api/developer/apis`) con su estado de conexión frontend/backend.
class DeveloperApisScreen extends ConsumerStatefulWidget {
  const DeveloperApisScreen({super.key});

  @override
  ConsumerState<DeveloperApisScreen> createState() =>
      _DeveloperApisScreenState();
}

class _DeveloperApisScreenState extends ConsumerState<DeveloperApisScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  /// Filtro por estado de frontend. `null` = todas.
  String? _frontendFilter;

  /// Filtro por módulo. `null` = todos.
  String? _moduleFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DevApi> _applyFilters(List<DevApi> apis) {
    final q = _query.trim().toLowerCase();
    return apis.where((a) {
      if (_frontendFilter != null && a.frontendStatus != _frontendFilter) {
        return false;
      }
      if (_moduleFilter != null && a.moduleKey != _moduleFilter) return false;
      if (q.isEmpty) return true;
      final haystack = [
        a.path,
        a.action ?? '',
        a.summary ?? '',
        a.moduleKey ?? '',
        a.method,
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final apisAsync = ref.watch(developerApisProvider);

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('APIs por conectar'),
      ),
      child: SafeArea(
        bottom: false,
        child: apisAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateView(message: '$e'),
          data: (apis) {
            final modules = {
              for (final a in apis)
                if (a.moduleKey != null) a.moduleKey!,
            }.toList()
              ..sort();
            final filtered = _applyFilters(apis);

            return RefreshIndicator(
              color: palette.limeDeep,
              onRefresh: () async => ref.invalidate(developerApisProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _SummaryBar(apis: apis),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar por ruta, acción o módulo…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FrontendFilters(
                    apis: apis,
                    selected: _frontendFilter,
                    onSelect: (v) => setState(() => _frontendFilter = v),
                  ),
                  if (modules.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _ModuleFilter(
                      modules: modules,
                      selected: _moduleFilter,
                      onChanged: (v) => setState(() => _moduleFilter = v),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        '${filtered.length} de ${apis.length}',
                        style: context.textTheme.labelLarge?.copyWith(
                          color: palette.textMuted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      if (_frontendFilter != null ||
                          _moduleFilter != null ||
                          _query.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                              _frontendFilter = null;
                              _moduleFilter = null;
                            });
                          },
                          icon: const Icon(Icons.filter_alt_off_outlined,
                              size: 18,),
                          label: const Text('Limpiar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (filtered.isEmpty)
                    const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'Sin resultados',
                      subtitle: 'Ninguna API coincide con los filtros.',
                    )
                  else
                    for (final a in filtered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ApiTile(api: a),
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.apis});
  final List<DevApi> apis;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final connected =
        apis.where((a) => a.frontendStatus == 'connected').length;
    final pending = apis.where((a) => a.frontendStatus == 'pending').length;
    final blocked = apis.where((a) => a.frontendStatus == 'blocked').length;

    return EduCard(
      color: palette.cardContrast,
      child: Row(
        children: [
          Expanded(
            child: _SummaryStat(
              value: '$pending',
              label: 'Por conectar',
              color: palette.lime,
            ),
          ),
          _divider(),
          Expanded(
            child: _SummaryStat(
              value: '$connected',
              label: 'Conectadas',
              color: palette.success,
            ),
          ),
          _divider(),
          Expanded(
            child: _SummaryStat(
              value: '$blocked',
              label: 'Bloqueadas',
              color: blocked > 0 ? palette.danger : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 40,
        color: Colors.white.withValues(alpha: 0.15),
      );
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat(
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
          style: context.textTheme.headlineSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.labelSmall
              ?.copyWith(color: Colors.white.withValues(alpha: 0.7)),
        ),
      ],
    );
  }
}

class _FrontendFilters extends StatelessWidget {
  const _FrontendFilters({
    required this.apis,
    required this.selected,
    required this.onSelect,
  });
  final List<DevApi> apis;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    int countOf(String? s) =>
        s == null ? apis.length : apis.where((a) => a.frontendStatus == s).length;

    final options = <(String?, String)>[
      (null, 'Todas'),
      ('pending', 'Por conectar'),
      ('connected', 'Conectadas'),
      ('blocked', 'Bloqueadas'),
      ('not_needed', 'No requeridas'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in options)
          FilterChip(
            selected: selected == value,
            label: Text('$label · ${countOf(value)}'),
            onSelected: (_) => onSelect(value),
          ),
      ],
    );
  }
}

class _ModuleFilter extends StatelessWidget {
  const _ModuleFilter({
    required this.modules,
    required this.selected,
    required this.onChanged,
  });
  final List<String> modules;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Icon(Icons.widgets_outlined, size: 18, color: palette.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: selected,
              hint: const Text('Todos los módulos'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todos los módulos'),
                ),
                for (final m in modules)
                  DropdownMenuItem<String?>(value: m, child: Text(m)),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _ApiTile extends StatelessWidget {
  const _ApiTile({required this.api});
  final DevApi api;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EduCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MethodBadge(method: api.method),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  api.action ?? api.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          if (api.action != null) ...[
            const SizedBox(height: 4),
            Text(
              api.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelSmall?.copyWith(
                color: palette.textMuted,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (api.summary != null) ...[
            const SizedBox(height: 6),
            Text(api.summary!, style: context.textTheme.bodySmall),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusPill(
                label: 'FE: ${_frontendLabel(api.frontendStatus)}',
                color: _frontendColor(api.frontendStatus, palette),
              ),
              _StatusPill(
                label: 'BE: ${_backendLabel(api.backendStatus)}',
                color: _backendColor(api.backendStatus, palette),
              ),
              if (api.moduleKey != null)
                _Meta(icon: Icons.widgets_outlined, text: api.moduleKey!),
              if (api.priority != null)
                _Meta(
                  icon: Icons.flag_outlined,
                  text: _priorityLabel(api.priority!),
                  color: _priorityColor(api.priority!, palette),
                ),
              if (api.owner != null)
                _Meta(icon: Icons.person_outline_rounded, text: api.owner!),
            ],
          ),
          if (api.notes != null && api.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: palette.textMuted,),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    api.notes!,
                    style: context.textTheme.labelSmall
                        ?.copyWith(color: palette.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.method});
  final String method;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (method) {
      'GET' => palette.info,
      'POST' => palette.success,
      'PATCH' || 'PUT' => palette.warning,
      'DELETE' => palette.danger,
      _ => palette.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        method,
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
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

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.color});
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

String _frontendLabel(String s) => switch (s) {
      'connected' => 'Conectada',
      'blocked' => 'Bloqueada',
      'not_needed' => 'No requerida',
      _ => 'Pendiente',
    };

Color _frontendColor(String s, AppPalette palette) => switch (s) {
      'connected' => palette.success,
      'blocked' => palette.danger,
      'not_needed' => palette.textMuted,
      _ => palette.warning,
    };

String _backendLabel(String s) => switch (s) {
      'implemented' => 'Implementada',
      'blocked' => 'Bloqueada',
      'deprecated' => 'Obsoleta',
      _ => 'Planeada',
    };

Color _backendColor(String s, AppPalette palette) => switch (s) {
      'implemented' => palette.success,
      'blocked' => palette.danger,
      'deprecated' => palette.textMuted,
      _ => palette.info,
    };

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
