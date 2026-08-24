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

/// Área "Feature flags": lista con toggle inline de `enabled`, CRUD y rollout,
/// sobre `/api/developer/feature-flags`.
class DeveloperFeatureFlagsScreen extends ConsumerStatefulWidget {
  const DeveloperFeatureFlagsScreen({super.key});

  @override
  ConsumerState<DeveloperFeatureFlagsScreen> createState() =>
      _DeveloperFeatureFlagsScreenState();
}

class _DeveloperFeatureFlagsScreenState
    extends ConsumerState<DeveloperFeatureFlagsScreen> {
  bool _busy = false;

  void _refresh() {
    ref.invalidate(developerFeatureFlagsProvider);
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

  Future<void> _toggle(DevFeatureFlag flag, bool value) async {
    final repo = ref.read(developerRepositoryProvider);
    await _run(
      () => repo.updateFeatureFlag(flag.id, {'enabled': value}),
      value ? 'Flag activado.' : 'Flag desactivado.',
    );
  }

  Future<void> _openForm({DevFeatureFlag? flag}) async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _FlagFormSheet(flag: flag),
    );
    if (payload == null) return;
    final repo = ref.read(developerRepositoryProvider);
    if (flag == null) {
      await _run(() => repo.createFeatureFlag(payload), 'Flag creado.');
    } else {
      await _run(
          () => repo.updateFeatureFlag(flag.id, payload), 'Flag actualizado.',);
    }
  }

  Future<void> _archive(DevFeatureFlag flag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archivar flag'),
        content: Text('¿Archivar “${flag.title}”? Dejará de aparecer en la '
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
    await _run(() => repo.archiveFeatureFlag(flag.id), 'Flag archivado.');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final flagsAsync = ref.watch(developerFeatureFlagsProvider);

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Feature flags'),
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
            flagsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorStateView(message: '$e'),
              data: (flags) {
                final active = flags.where((f) => f.enabled).length;
                return RefreshIndicator(
                  color: palette.limeDeep,
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      if (flags.isNotEmpty)
                        Text(
                          '$active de ${flags.length} activos',
                          style: context.textTheme.labelLarge?.copyWith(
                            color: palette.textMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (flags.isEmpty)
                        const EmptyState(
                          icon: Icons.flag_outlined,
                          title: 'Sin feature flags',
                          subtitle: 'Crea el primero con el botón “Nuevo”.',
                        )
                      else
                        for (final f in flags)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _FlagCard(
                              flag: f,
                              busy: _busy,
                              onToggle: (v) => _toggle(f, v),
                              onEdit: () => _openForm(flag: f),
                              onArchive: () => _archive(f),
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

class _FlagCard extends StatelessWidget {
  const _FlagCard({
    required this.flag,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onArchive,
  });
  final DevFeatureFlag flag;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EduCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      flag.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      flag.flagKey,
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
              Switch(
                value: flag.enabled,
                onChanged: busy ? null : onToggle,
              ),
              _FlagMenu(onEdit: onEdit, onArchive: onArchive),
            ],
          ),
          if (flag.description != null && flag.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              flag.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall
                  ?.copyWith(color: palette.textMuted),
            ),
          ],
          if (flag.rolloutPercent != null) ...[
            const SizedBox(height: 10),
            _RolloutBar(percent: flag.rolloutPercent!),
          ],
        ],
      ),
    );
  }
}

class _RolloutBar extends StatelessWidget {
  const _RolloutBar({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final clamped = percent.clamp(0, 100);
    return Row(
      children: [
        Icon(Icons.rocket_launch_outlined, size: 14, color: palette.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: clamped / 100,
              minHeight: 6,
              backgroundColor: palette.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(palette.limeDeep),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$clamped%',
          style: context.textTheme.labelSmall
              ?.copyWith(fontWeight: FontWeight.w800, color: palette.textMuted),
        ),
      ],
    );
  }
}

class _FlagMenu extends StatelessWidget {
  const _FlagMenu({required this.onEdit, required this.onArchive});
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
class _FlagFormSheet extends StatefulWidget {
  const _FlagFormSheet({this.flag});
  final DevFeatureFlag? flag;

  @override
  State<_FlagFormSheet> createState() => _FlagFormSheetState();
}

class _FlagFormSheetState extends State<_FlagFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _flagKey;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late bool _enabled;
  late double _rollout;

  bool get _isEdit => widget.flag != null;

  @override
  void initState() {
    super.initState();
    final f = widget.flag;
    _flagKey = TextEditingController(text: f?.flagKey ?? '');
    _title = TextEditingController(text: f?.title ?? '');
    _description = TextEditingController(text: f?.description ?? '');
    _enabled = f?.enabled ?? false;
    _rollout = (f?.rolloutPercent ?? 100).toDouble();
  }

  @override
  void dispose() {
    _flagKey.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  String? _trimOrNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, <String, dynamic>{
      'flag_key': _flagKey.text.trim(),
      'title': _title.text.trim(),
      'description': _trimOrNull(_description),
      'enabled': _enabled,
      'rollout_percent': _rollout.round(),
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
                _isEdit ? 'Editar flag' : 'Nuevo flag',
                style: context.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _flagKey,
                decoration: const InputDecoration(
                  labelText: 'Clave *',
                  hintText: 'new_gradebook',
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
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activado'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('Rollout', style: context.textTheme.labelLarge),
                  const Spacer(),
                  Text('${_rollout.round()}%',
                      style: context.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w800),),
                ],
              ),
              Slider(
                value: _rollout,
                max: 100,
                divisions: 20,
                label: '${_rollout.round()}%',
                onChanged: (v) => setState(() => _rollout = v),
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
