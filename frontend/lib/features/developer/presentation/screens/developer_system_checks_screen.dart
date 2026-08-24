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

const _statuses = <String>[
  'unknown',
  'passing',
  'warning',
  'failing',
  'disabled',
];
const _severities = <String>['low', 'medium', 'high', 'critical'];
const _checkTypes = <String>['manual', 'sql', 'http', 'script'];

/// Área "System checks": lista con estado/severidad + CRUD, sobre
/// `/api/developer/system-checks`.
class DeveloperSystemChecksScreen extends ConsumerStatefulWidget {
  const DeveloperSystemChecksScreen({super.key});

  @override
  ConsumerState<DeveloperSystemChecksScreen> createState() =>
      _DeveloperSystemChecksScreenState();
}

class _DeveloperSystemChecksScreenState
    extends ConsumerState<DeveloperSystemChecksScreen> {
  String? _statusFilter;
  bool _busy = false;

  void _refresh() {
    ref.invalidate(developerSystemChecksProvider);
    ref.invalidate(developerSummaryProvider);
  }

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _refresh();
      _snack(okMessage);
    } catch (e) {
      if (mounted) _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? context.palette.danger : null,
      ),
    );
  }

  Future<void> _toggle(DevSystemCheck check, bool value) async {
    final repo = ref.read(developerRepositoryProvider);
    await _run(
      () => repo.updateSystemCheck(check.id, {'enabled': value}),
      value ? 'Check habilitado.' : 'Check deshabilitado.',
    );
  }

  Future<void> _openForm({DevSystemCheck? check}) async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CheckFormSheet(check: check),
    );
    if (payload == null) return;
    final repo = ref.read(developerRepositoryProvider);
    if (check == null) {
      await _run(() => repo.createSystemCheck(payload), 'Check creado.');
    } else {
      await _run(() => repo.updateSystemCheck(check.id, payload),
          'Check actualizado.',);
    }
  }

  Future<void> _archive(DevSystemCheck check) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archivar check'),
        content: Text('¿Archivar “${check.title}”? Dejará de aparecer en la '
            'lista.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = ref.read(developerRepositoryProvider);
    await _run(() => repo.archiveSystemCheck(check.id), 'Check archivado.');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final checksAsync = ref.watch(developerSystemChecksProvider);

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('System checks'),
      ),
      fab: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo'),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            checksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorStateView(message: '$e'),
              data: (checks) {
                final filtered = _statusFilter == null
                    ? checks
                    : checks.where((c) => c.status == _statusFilter).toList();
                return RefreshIndicator(
                  color: palette.limeDeep,
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      _HealthBar(checks: checks),
                      const SizedBox(height: 12),
                      _StatusFilters(
                        checks: checks,
                        selected: _statusFilter,
                        onSelect: (v) => setState(() => _statusFilter = v),
                      ),
                      const SizedBox(height: 14),
                      if (filtered.isEmpty)
                        EmptyState(
                          icon: Icons.health_and_safety_outlined,
                          title: 'Sin chequeos',
                          subtitle: _statusFilter == null
                              ? 'Crea el primero con el botón “Nuevo”.'
                              : 'Ninguno en este estado.',
                        )
                      else
                        for (final c in filtered)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _CheckCard(
                              check: c,
                              busy: _busy,
                              onToggle: (v) => _toggle(c, v),
                              onEdit: () => _openForm(check: c),
                              onArchive: () => _archive(c),
                            ),
                          ),
                    ],
                  ),
                );
              },
            ),
            if (_busy)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 3),
              ),
          ],
        ),
      ),
    );
  }
}

class _HealthBar extends StatelessWidget {
  const _HealthBar({required this.checks});
  final List<DevSystemCheck> checks;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final passing = checks.where((c) => c.status == 'passing').length;
    final warning = checks.where((c) => c.status == 'warning').length;
    final failing = checks.where((c) => c.status == 'failing').length;

    return EduCard(
      color: palette.cardContrast,
      child: Row(
        children: [
          Expanded(
            child: _HealthStat(
              value: '$passing',
              label: 'OK',
              color: palette.success,
            ),
          ),
          _divider(),
          Expanded(
            child: _HealthStat(
              value: '$warning',
              label: 'Advertencia',
              color: warning > 0 ? palette.warning : Colors.white,
            ),
          ),
          _divider(),
          Expanded(
            child: _HealthStat(
              value: '$failing',
              label: 'Fallando',
              color: failing > 0 ? palette.danger : Colors.white,
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

class _HealthStat extends StatelessWidget {
  const _HealthStat(
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.labelSmall
              ?.copyWith(color: Colors.white.withValues(alpha: 0.7)),
        ),
      ],
    );
  }
}

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({
    required this.checks,
    required this.selected,
    required this.onSelect,
  });
  final List<DevSystemCheck> checks;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    int countOf(String? s) =>
        s == null ? checks.length : checks.where((c) => c.status == s).length;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          selected: selected == null,
          label: Text('Todos · ${countOf(null)}'),
          onSelected: (_) => onSelect(null),
        ),
        for (final s in _statuses)
          FilterChip(
            selected: selected == s,
            label: Text('${statusLabel(s)} · ${countOf(s)}'),
            onSelected: (_) => onSelect(s),
          ),
      ],
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({
    required this.check,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onArchive,
  });
  final DevSystemCheck check;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (statusColor, statusText, statusIcon) =
        statusVisual(check.status, palette);
    return EduCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(statusIcon, color: statusColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      check.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      check.checkKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: palette.textMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Pill(label: statusText, color: statusColor),
              _CheckMenu(onEdit: onEdit, onArchive: onArchive),
            ],
          ),
          if (check.description != null && check.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              check.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall
                  ?.copyWith(color: palette.textMuted),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (check.severity != null)
                _Pill(
                  label: severityLabel(check.severity!),
                  color: severityColor(check.severity!, palette),
                ),
              if (check.checkType != null)
                _Meta(
                    icon: Icons.category_outlined,
                    text: typeLabel(check.checkType!),),
              if (check.target != null && check.target!.isNotEmpty)
                _Meta(icon: Icons.gps_fixed_rounded, text: check.target!),
              if (!check.enabled)
                _Meta(
                  icon: Icons.pause_circle_outline_rounded,
                  text: 'Deshabilitado',
                  color: palette.textMuted,
                ),
              _Meta(
                icon: Icons.schedule_rounded,
                text: _relative(check.lastCheckedAt),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Habilitado', style: context.textTheme.labelMedium),
              const Spacer(),
              Switch(
                value: check.enabled,
                onChanged: busy ? null : onToggle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckMenu extends StatelessWidget {
  const _CheckMenu({required this.onEdit, required this.onArchive});
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      tooltip: 'Acciones',
      onSelected: (v) {
        switch (v) {
          case 'edit':
            onEdit();
          case 'archive':
            onArchive();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: Text('Editar'),
          ),
        ),
        const PopupMenuItem(
          value: 'archive',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.archive_outlined),
            title: Text('Archivar'),
          ),
        ),
      ],
    );
  }
}

/// Formulario de creación/edición. Devuelve el payload (snake_case) al guardar.
class _CheckFormSheet extends StatefulWidget {
  const _CheckFormSheet({this.check});
  final DevSystemCheck? check;

  @override
  State<_CheckFormSheet> createState() => _CheckFormSheetState();
}

class _CheckFormSheetState extends State<_CheckFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _checkKey;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _target;
  late String _checkType;
  late String _severity;
  late String _status;
  late bool _enabled;

  bool get _isEdit => widget.check != null;

  @override
  void initState() {
    super.initState();
    final c = widget.check;
    _checkKey = TextEditingController(text: c?.checkKey ?? '');
    _title = TextEditingController(text: c?.title ?? '');
    _description = TextEditingController(text: c?.description ?? '');
    _target = TextEditingController(text: c?.target ?? '');
    _checkType = c?.checkType ?? 'manual';
    _severity = c?.severity ?? 'medium';
    _status = c?.status ?? 'unknown';
    _enabled = c?.enabled ?? true;
  }

  @override
  void dispose() {
    _checkKey.dispose();
    _title.dispose();
    _description.dispose();
    _target.dispose();
    super.dispose();
  }

  String? _trimOrNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, <String, dynamic>{
      'check_key': _checkKey.text.trim(),
      'title': _title.text.trim(),
      'description': _trimOrNull(_description),
      'check_type': _checkType,
      'target': _trimOrNull(_target),
      'severity': _severity,
      'status': _status,
      'enabled': _enabled,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEdit ? 'Editar check' : 'Nuevo check',
                style: context.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _checkKey,
                decoration: const InputDecoration(
                  labelText: 'Clave *',
                  hintText: 'db_connection',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'La clave es obligatoria.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Título *'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'El título es obligatorio.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _checkType,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Tipo'),
                      items: [
                        for (final t in _checkTypes)
                          DropdownMenuItem(value: t, child: Text(typeLabel(t))),
                      ],
                      onChanged: (v) =>
                          setState(() => _checkType = v ?? _checkType),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _severity,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Severidad'),
                      items: [
                        for (final s in _severities)
                          DropdownMenuItem(
                              value: s, child: Text(severityLabel(s)),),
                      ],
                      onChanged: (v) => setState(() => _severity = v ?? _severity),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: [
                  for (final s in _statuses)
                    DropdownMenuItem(value: s, child: Text(statusLabel(s))),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _target,
                decoration: const InputDecoration(
                  labelText: 'Objetivo',
                  hintText: 'SELECT 1 · /health · script.sh',
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Habilitado'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: Text(_isEdit ? 'Guardar' : 'Crear'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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

String statusLabel(String s) => switch (s) {
      'passing' => 'OK',
      'warning' => 'Advertencia',
      'failing' => 'Fallando',
      'disabled' => 'Deshabilitado',
      _ => 'Desconocido',
    };

(Color, String, IconData) statusVisual(String status, AppPalette palette) =>
    switch (status) {
      'passing' => (palette.success, 'OK', Icons.check_circle_outline_rounded),
      'warning' => (palette.warning, 'Advertencia', Icons.warning_amber_rounded),
      'failing' => (palette.danger, 'Fallando', Icons.error_outline_rounded),
      'disabled' => (
          palette.textMuted,
          'Deshabilitado',
          Icons.pause_circle_outline_rounded
        ),
      _ => (palette.info, 'Desconocido', Icons.help_outline_rounded),
    };

String severityLabel(String s) => switch (s) {
      'critical' => 'Crítica',
      'high' => 'Alta',
      'medium' => 'Media',
      _ => 'Baja',
    };

Color severityColor(String s, AppPalette palette) => switch (s) {
      'critical' => palette.danger,
      'high' => palette.warning,
      'medium' => palette.info,
      _ => palette.textMuted,
    };

String typeLabel(String t) => switch (t) {
      'sql' => 'SQL',
      'http' => 'HTTP',
      'script' => 'Script',
      _ => 'Manual',
    };

String _relative(DateTime? d) {
  if (d == null) return 'Sin ejecutar';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return DateFormat('d MMM, HH:mm', 'es').format(d);
}
