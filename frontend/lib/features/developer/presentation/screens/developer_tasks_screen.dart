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

/// Estados de tarea, en orden lógico de flujo.
const _taskStatuses = <String>[
  'pending',
  'ready',
  'in_progress',
  'blocked',
  'done',
  'cancelled',
];

const _priorities = <String>['low', 'medium', 'high', 'critical'];

/// Área "Tareas técnicas": lista + CRUD + cambio de estado, sobre
/// `/api/developer/tasks`.
class DeveloperTasksScreen extends ConsumerStatefulWidget {
  const DeveloperTasksScreen({super.key});

  @override
  ConsumerState<DeveloperTasksScreen> createState() =>
      _DeveloperTasksScreenState();
}

class _DeveloperTasksScreenState extends ConsumerState<DeveloperTasksScreen> {
  /// Filtro por estado. `null` = todas.
  String? _statusFilter;
  bool _busy = false;

  void _refresh() {
    ref.invalidate(developerTasksProvider);
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

  Future<void> _openForm({DevTask? task}) async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _TaskFormSheet(task: task),
    );
    if (payload == null) return;
    final repo = ref.read(developerRepositoryProvider);
    if (task == null) {
      await _run(() => repo.createTask(payload), 'Tarea creada.');
    } else {
      await _run(() => repo.updateTask(task.id, payload), 'Tarea actualizada.');
    }
  }

  Future<void> _changeStatus(DevTask task) async {
    final newStatus = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _StatusPickerSheet(current: task.status),
    );
    if (newStatus == null || newStatus == task.status) return;
    final repo = ref.read(developerRepositoryProvider);
    await _run(
      () => repo.updateTask(task.id, {
        'status': newStatus,
        if (newStatus == 'done') 'completed_at': DateTime.now().toIso8601String(),
      }),
      'Estado actualizado.',
    );
  }

  Future<void> _archive(DevTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archivar tarea'),
        content: Text('¿Archivar “${task.title}”? Dejará de aparecer en la '
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
    await _run(() => repo.archiveTask(task.id), 'Tarea archivada.');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tasksAsync = ref.watch(developerTasksProvider);

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Tareas técnicas'),
      ),
      fab: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva'),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorStateView(message: '$e'),
              data: (tasks) {
                final filtered = _statusFilter == null
                    ? tasks
                    : tasks.where((t) => t.status == _statusFilter).toList();
                return RefreshIndicator(
                  color: palette.limeDeep,
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      _StatusFilters(
                        tasks: tasks,
                        selected: _statusFilter,
                        onSelect: (v) => setState(() => _statusFilter = v),
                      ),
                      const SizedBox(height: 14),
                      if (filtered.isEmpty)
                        EmptyState(
                          icon: Icons.task_alt_outlined,
                          title: 'Sin tareas',
                          subtitle: _statusFilter == null
                              ? 'Crea la primera con el botón “Nueva”.'
                              : 'Ninguna tarea en este estado.',
                        )
                      else
                        for (final t in filtered)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _TaskCard(
                              task: t,
                              onEdit: () => _openForm(task: t),
                              onChangeStatus: () => _changeStatus(t),
                              onArchive: () => _archive(t),
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

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({
    required this.tasks,
    required this.selected,
    required this.onSelect,
  });
  final List<DevTask> tasks;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    int countOf(String? s) =>
        s == null ? tasks.length : tasks.where((t) => t.status == s).length;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          selected: selected == null,
          label: Text('Todas · ${countOf(null)}'),
          onSelected: (_) => onSelect(null),
        ),
        for (final s in _taskStatuses)
          FilterChip(
            selected: selected == s,
            label: Text('${statusLabel(s)} · ${countOf(s)}'),
            onSelected: (_) => onSelect(s),
          ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onEdit,
    required this.onChangeStatus,
    required this.onArchive,
  });
  final DevTask task;
  final VoidCallback onEdit;
  final VoidCallback onChangeStatus;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (statusColor, label) = statusVisual(task.status, palette);
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
                child: Text(
                  task.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              _Pill(label: label, color: statusColor),
              _TaskMenu(
                onEdit: onEdit,
                onChangeStatus: onChangeStatus,
                onArchive: onArchive,
              ),
            ],
          ),
          if (task.description != null && task.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              task.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall
                  ?.copyWith(color: palette.textMuted),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (task.priority != null)
                _Meta(
                  icon: Icons.flag_outlined,
                  text: priorityLabel(task.priority!),
                  color: priorityColor(task.priority!, palette),
                ),
              if (task.moduleKey != null)
                _Meta(icon: Icons.widgets_outlined, text: task.moduleKey!),
              if (task.owner != null)
                _Meta(icon: Icons.person_outline_rounded, text: task.owner!),
              if (task.frontendRequired)
                const _Meta(icon: Icons.phone_iphone_rounded, text: 'Frontend'),
              _Meta(
                icon: task.backendReady
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                text: task.backendReady ? 'Backend listo' : 'Backend pendiente',
                color: task.backendReady ? palette.success : palette.textMuted,
              ),
              if (task.dueAt != null)
                _Meta(
                  icon: Icons.event_outlined,
                  text: DateFormat('d MMM', 'es').format(task.dueAt!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskMenu extends StatelessWidget {
  const _TaskMenu({
    required this.onEdit,
    required this.onChangeStatus,
    required this.onArchive,
  });
  final VoidCallback onEdit;
  final VoidCallback onChangeStatus;
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
          case 'status':
            onChangeStatus();
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
          value: 'status',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.swap_horiz_rounded),
            title: Text('Cambiar estado'),
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

/// Hoja para elegir un nuevo estado.
class _StatusPickerSheet extends StatelessWidget {
  const _StatusPickerSheet({required this.current});
  final String current;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text('Cambiar estado',
                    style: context.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),),
              ],
            ),
          ),
          for (final s in _taskStatuses)
            ListTile(
              leading: Icon(
                s == current
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: s == current
                    ? palette.limeDeep
                    : palette.textMuted,
              ),
              title: Text(statusLabel(s)),
              trailing: _Pill(
                label: statusLabel(s),
                color: statusVisual(s, palette).$1,
              ),
              onTap: () => Navigator.pop(context, s),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Formulario de creación/edición de tarea. Devuelve el payload (snake_case)
/// al hacer "Guardar", o `null` al cancelar.
class _TaskFormSheet extends StatefulWidget {
  const _TaskFormSheet({this.task});
  final DevTask? task;

  @override
  State<_TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends State<_TaskFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _moduleKey;
  late final TextEditingController _owner;
  late final TextEditingController _notes;
  late String _status;
  late String _priority;
  late bool _frontendRequired;
  late bool _backendReady;
  DateTime? _dueAt;

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _description = TextEditingController(text: t?.description ?? '');
    _moduleKey = TextEditingController(text: t?.moduleKey ?? '');
    _owner = TextEditingController(text: t?.owner ?? '');
    _notes = TextEditingController(text: t?.notes ?? '');
    _status = t?.status ?? 'pending';
    _priority = t?.priority ?? 'medium';
    _frontendRequired = t?.frontendRequired ?? true;
    _backendReady = t?.backendReady ?? false;
    _dueAt = t?.dueAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _moduleKey.dispose();
    _owner.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _trimOrNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, <String, dynamic>{
      'title': _title.text.trim(),
      'description': _trimOrNull(_description),
      'module_key': _trimOrNull(_moduleKey),
      'owner': _trimOrNull(_owner),
      'notes': _trimOrNull(_notes),
      'status': _status,
      'priority': _priority,
      'frontend_required': _frontendRequired,
      'backend_ready': _backendReady,
      'due_at': _dueAt?.toIso8601String(),
    });
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
                _isEdit ? 'Editar tarea' : 'Nueva tarea',
                style: context.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Título *',
                  hintText: 'Qué hay que hacer',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'El título es obligatorio.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _status,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Estado'),
                      items: [
                        for (final s in _taskStatuses)
                          DropdownMenuItem(value: s, child: Text(statusLabel(s))),
                      ],
                      onChanged: (v) => setState(() => _status = v ?? _status),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _priority,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Prioridad'),
                      items: [
                        for (final p in _priorities)
                          DropdownMenuItem(
                              value: p, child: Text(priorityLabel(p)),),
                      ],
                      onChanged: (v) => setState(() => _priority = v ?? _priority),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _moduleKey,
                      decoration: const InputDecoration(
                        labelText: 'Módulo',
                        hintText: 'grades, chat…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _owner,
                      decoration: const InputDecoration(labelText: 'Responsable'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Requiere frontend'),
                value: _frontendRequired,
                onChanged: (v) => setState(() => _frontendRequired = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Backend listo'),
                value: _backendReady,
                onChanged: (v) => setState(() => _backendReady = v),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: _pickDue,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Fecha límite',
                    suffixIcon: _dueAt == null
                        ? const Icon(Icons.event_outlined)
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() => _dueAt = null),
                          ),
                  ),
                  child: Text(
                    _dueAt == null
                        ? 'Sin fecha'
                        : DateFormat('d MMM y', 'es').format(_dueAt!),
                    style: TextStyle(
                      color: _dueAt == null ? palette.textMuted : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notas'),
              ),
              const SizedBox(height: 20),
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
      'ready' => 'Listo',
      'in_progress' => 'En progreso',
      'blocked' => 'Bloqueado',
      'done' => 'Hecho',
      'cancelled' => 'Cancelado',
      _ => 'Pendiente',
    };

(Color, String) statusVisual(String status, AppPalette palette) => switch (status) {
      'in_progress' => (palette.info, 'En progreso'),
      'ready' => (palette.limeDeep, 'Listo'),
      'blocked' => (palette.danger, 'Bloqueado'),
      'done' => (palette.success, 'Hecho'),
      'cancelled' => (palette.textMuted, 'Cancelado'),
      _ => (palette.warning, 'Pendiente'),
    };

String priorityLabel(String p) => switch (p) {
      'critical' => 'Crítica',
      'high' => 'Alta',
      'medium' => 'Media',
      _ => 'Baja',
    };

Color priorityColor(String p, AppPalette palette) => switch (p) {
      'critical' => palette.danger,
      'high' => palette.warning,
      'medium' => palette.info,
      _ => palette.textMuted,
    };
