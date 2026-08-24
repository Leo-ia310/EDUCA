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

/// Área "Módulos": CRUD del catálogo de módulos del dashboard, sobre
/// `/api/developer/modules`.
class DeveloperModulesScreen extends ConsumerStatefulWidget {
  const DeveloperModulesScreen({super.key});

  @override
  ConsumerState<DeveloperModulesScreen> createState() =>
      _DeveloperModulesScreenState();
}

class _DeveloperModulesScreenState
    extends ConsumerState<DeveloperModulesScreen> {
  bool _busy = false;

  void _refresh() {
    ref.invalidate(developerModulesProvider);
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

  Future<void> _toggle(DevModule module, bool value) async {
    final repo = ref.read(developerRepositoryProvider);
    await _run(
      () => repo.updateModule(module.id, {'enabled': value}),
      value ? 'Módulo habilitado.' : 'Módulo deshabilitado.',
    );
  }

  Future<void> _openForm({DevModule? module}) async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ModuleFormSheet(module: module),
    );
    if (payload == null) return;
    final repo = ref.read(developerRepositoryProvider);
    if (module == null) {
      await _run(() => repo.createModule(payload), 'Módulo creado.');
    } else {
      await _run(
          () => repo.updateModule(module.id, payload), 'Módulo actualizado.',);
    }
  }

  Future<void> _archive(DevModule module) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archivar módulo'),
        content: Text('¿Archivar “${module.title}”? Dejará de aparecer en la '
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
    await _run(() => repo.archiveModule(module.id), 'Módulo archivado.');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final modulesAsync = ref.watch(developerModulesProvider);

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Módulos'),
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
            modulesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorStateView(message: '$e'),
              data: (modules) {
                // Ordena por display_order y luego por título.
                final sorted = [...modules]..sort((a, b) {
                    final ao = a.displayOrder ?? 1 << 30;
                    final bo = b.displayOrder ?? 1 << 30;
                    if (ao != bo) return ao.compareTo(bo);
                    return a.title.compareTo(b.title);
                  });
                final active = modules.where((m) => m.enabled).length;
                return RefreshIndicator(
                  color: palette.limeDeep,
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      if (modules.isNotEmpty)
                        Text(
                          '$active de ${modules.length} habilitados',
                          style: context.textTheme.labelLarge?.copyWith(
                            color: palette.textMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (modules.isEmpty)
                        const EmptyState(
                          icon: Icons.widgets_outlined,
                          title: 'Sin módulos',
                          subtitle: 'Crea el primero con el botón “Nuevo”.',
                        )
                      else
                        for (final m in sorted)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ModuleCard(
                              module: m,
                              busy: _busy,
                              onToggle: (v) => _toggle(m, v),
                              onEdit: () => _openForm(module: m),
                              onArchive: () => _archive(m),
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

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.module,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onArchive,
  });
  final DevModule module;
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
                      module.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      module.moduleKey,
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
                value: module.enabled,
                onChanged: busy ? null : onToggle,
              ),
              _ModuleMenu(onEdit: onEdit, onArchive: onArchive),
            ],
          ),
          if (module.description != null && module.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              module.description!,
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
              if (module.category != null)
                _Meta(icon: Icons.category_outlined, text: module.category!),
              if (module.frontendRoute != null &&
                  module.frontendRoute!.isNotEmpty)
                _Meta(icon: Icons.route_outlined, text: module.frontendRoute!),
              if (module.displayOrder != null)
                _Meta(
                    icon: Icons.sort_rounded,
                    text: 'Orden ${module.displayOrder}',),
            ],
          ),
          if (module.requiredRoles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in module.requiredRoles)
                  _RolePill(role: r),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 12, color: palette.info),
          const SizedBox(width: 3),
          Text(
            role,
            style: context.textTheme.labelSmall?.copyWith(
              color: palette.info,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleMenu extends StatelessWidget {
  const _ModuleMenu({required this.onEdit, required this.onArchive});
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
class _ModuleFormSheet extends StatefulWidget {
  const _ModuleFormSheet({this.module});
  final DevModule? module;

  @override
  State<_ModuleFormSheet> createState() => _ModuleFormSheetState();
}

class _ModuleFormSheetState extends State<_ModuleFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _moduleKey;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _icon;
  late final TextEditingController _frontendRoute;
  late final TextEditingController _requiredRoles;
  late final TextEditingController _displayOrder;
  late bool _enabled;

  bool get _isEdit => widget.module != null;

  @override
  void initState() {
    super.initState();
    final m = widget.module;
    _moduleKey = TextEditingController(text: m?.moduleKey ?? '');
    _title = TextEditingController(text: m?.title ?? '');
    _description = TextEditingController(text: m?.description ?? '');
    _category = TextEditingController(text: m?.category ?? '');
    _icon = TextEditingController(text: m?.icon ?? '');
    _frontendRoute = TextEditingController(text: m?.frontendRoute ?? '');
    _requiredRoles =
        TextEditingController(text: (m?.requiredRoles ?? const []).join(', '));
    _displayOrder =
        TextEditingController(text: m?.displayOrder?.toString() ?? '');
    _enabled = m?.enabled ?? true;
  }

  @override
  void dispose() {
    _moduleKey.dispose();
    _title.dispose();
    _description.dispose();
    _category.dispose();
    _icon.dispose();
    _frontendRoute.dispose();
    _requiredRoles.dispose();
    _displayOrder.dispose();
    super.dispose();
  }

  String? _trimOrNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final roles = _requiredRoles.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final order = int.tryParse(_displayOrder.text.trim());
    Navigator.pop(context, <String, dynamic>{
      'module_key': _moduleKey.text.trim(),
      'title': _title.text.trim(),
      'description': _trimOrNull(_description),
      'category': _trimOrNull(_category),
      'icon': _trimOrNull(_icon),
      'frontend_route': _trimOrNull(_frontendRoute),
      'required_roles': roles,
      'enabled': _enabled,
      'display_order': order,
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
                _isEdit ? 'Editar módulo' : 'Nuevo módulo',
                style: context.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _moduleKey,
                decoration: const InputDecoration(
                  labelText: 'Clave *',
                  hintText: 'assignments',
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
                    child: TextFormField(
                      controller: _category,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _icon,
                      decoration: const InputDecoration(
                        labelText: 'Icono',
                        hintText: 'assignment',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _frontendRoute,
                decoration: const InputDecoration(
                  labelText: 'Ruta frontend',
                  hintText: '/assignments',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _requiredRoles,
                decoration: const InputDecoration(
                  labelText: 'Roles requeridos',
                  hintText: 'admin, teacher (separados por coma)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _displayOrder,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Orden de despliegue',
                  hintText: '1',
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

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text}) : color = null;
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
