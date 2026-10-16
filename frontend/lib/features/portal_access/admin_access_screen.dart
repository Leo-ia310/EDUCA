import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/backend_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/depth_card.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../dashboard/presentation/widgets/student_chrome.dart';
import 'providers.dart';

class AdminAccessScreen extends ConsumerStatefulWidget {
  const AdminAccessScreen({super.key});
  @override
  ConsumerState<AdminAccessScreen> createState() => _AdminAccessScreenState();
}

class _AdminAccessScreenState extends ConsumerState<AdminAccessScreen> {
  bool _saving = false;
  Future<void> _save(Map<String, dynamic> payload) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(backendApiClientProvider)!
          .post('/portal-access/config', data: payload);
      ref.invalidate(portalAccessConfigProvider);
      ref.invalidate(portalAccessProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Accesos actualizados.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudieron guardar los accesos. $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> config, bool visibility) async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AccessRuleDialog(config: config, visibility: visibility),
    );
    if (payload != null) await _save(payload);
  }

  @override
  Widget build(BuildContext context) => StudentDetailScaffold(
        title: 'Accesos y visibilidad de notas',
        bottomNav: false,
        onRefresh: () async {
          ref.invalidate(portalAccessConfigProvider);
          await ref.read(portalAccessConfigProvider.future);
        },
        child: ref.watch(portalAccessConfigProvider).when(
              loading: () => const SkeletonList(),
              error: (e, _) => ErrorStateView(
                message: 'No se pudieron cargar los accesos. $e',
                onRetry: () => ref.invalidate(portalAccessConfigProvider),
              ),
              data: (data) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Configura accesos de alumnos y padres. Docentes y administración conservan el acceso académico.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _saving ? null : () => _edit(data, false),
                        icon: const Icon(Icons.tune_rounded),
                        label: const Text('Permisos por rol o usuario'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _saving ? null : () => _edit(data, true),
                        icon: const Icon(Icons.visibility_rounded),
                        label: const Text('Visibilidad de notas'),
                      ),
                    ],
                  ),
                  if (_saving) const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Permisos de módulos',
                    style: context.textTheme.titleMedium,
                  ),
                  const Text(
                    'Usuario > rol > institución. Sin una regla, el acceso está habilitado.',
                  ),
                  for (final rule in data['permissionRules'] as List)
                    _rule(data, Map<String, dynamic>.from(rule as Map), false),
                  if ((data['permissionRules'] as List).isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Sin restricciones de módulos.'),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Visibilidad de notas',
                    style: context.textTheme.titleMedium,
                  ),
                  const Text(
                    'Usuario > estudiante > grupo > rol > institución. Dentro del mismo alcance, el periodo específico tiene prioridad. El permiso Ver notas también debe estar activo.',
                  ),
                  for (final rule in data['visibilityRules'] as List)
                    _rule(data, Map<String, dynamic>.from(rule as Map), true),
                  if ((data['visibilityRules'] as List).isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Notas visibles según los permisos de cada usuario.',
                      ),
                    ),
                ],
              ),
            ),
      );
  Widget _rule(
    Map<String, dynamic> data,
    Map<String, dynamic> rule,
    bool visibility,
  ) {
    final target = _targetLabel(data, rule);
    final period =
        _lookup(data['periods'] as List, rule['academic_period_id']) ??
            'Todos los periodos';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DepthCard(
        soft: true,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              visibility
                  ? target
                  : '${portalPermissionLabels[rule['permission']]} · $target',
              style: context.textTheme.titleSmall,
            ),
            if (visibility) Text(period),
            Row(
              children: [
                Expanded(
                  child: Text(
                    visibility
                        ? (rule['allowed'] == true
                            ? 'Notas visibles'
                            : 'Notas ocultas')
                        : (rule['allowed'] == true
                            ? 'Acceso habilitado'
                            : 'Acceso deshabilitado'),
                    style: context.textTheme.labelLarge
                        ?.copyWith(color: context.palette.accent),
                  ),
                ),
                Switch(
                  value: rule['allowed'] == true,
                  onChanged: _saving
                      ? null
                      : (allowed) => _save({
                            'action': visibility
                                ? 'save_visibility'
                                : 'save_permission',
                            'scope': rule['scope'],
                            'role': rule['role_code'],
                            'userId': rule['user_id'],
                            'groupId': rule['group_id'],
                            'studentId': rule['student_id'],
                            'periodId': rule['academic_period_id'],
                            'permission': rule['permission'],
                            'allowed': allowed,
                          }),
                ),
              ],
            ),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => _save({
                        'action': visibility
                            ? 'delete_visibility'
                            : 'delete_permission',
                        'id': rule['id'],
                      }),
              child: const Text('Quitar regla y heredar configuración'),
            ),
          ],
        ),
      ),
    );
  }
}

String? _lookup(List<dynamic> rows, dynamic id) {
  for (final row in rows) {
    if (row['id'] == id) return row['name'] as String;
  }
  return null;
}

String _targetLabel(Map<String, dynamic> data, Map<String, dynamic> rule) =>
    switch (rule['scope']) {
      'institution' => 'Toda la institución',
      'role' => rule['role_code'] == 'parent' ? 'Padres' : 'Alumnos',
      'group' => _lookup(data['groups'] as List, rule['group_id']) ?? 'Grupo',
      'student' =>
        _lookup(data['students'] as List, rule['student_id']) ?? 'Estudiante',
      _ => _lookup(data['users'] as List, rule['user_id']) ?? 'Usuario',
    };

class _AccessRuleDialog extends StatefulWidget {
  const _AccessRuleDialog({required this.config, required this.visibility});
  final Map<String, dynamic> config;
  final bool visibility;
  @override
  State<_AccessRuleDialog> createState() => _AccessRuleDialogState();
}

class _AccessRuleDialogState extends State<_AccessRuleDialog> {
  String _scope = 'institution', _role = 'parent', _permission = 'grades.view';
  int? _target, _period;
  bool _allowed = false;
  @override
  Widget build(BuildContext context) {
    final rows = widget.config[_scope == 'group'
        ? 'groups'
        : _scope == 'student'
            ? 'students'
            : 'users'] as List;
    return AlertDialog(
      title: Text(
        widget.visibility
            ? 'Visibilidad de notas'
            : 'Permisos de alumnos y padres',
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _scope,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Aplicar a'),
                items: [
                  const DropdownMenuItem(
                    value: 'institution',
                    child: Text('Toda la institución'),
                  ),
                  const DropdownMenuItem(
                    value: 'role',
                    child: Text('Rol: padres o alumnos'),
                  ),
                  if (widget.visibility) ...[
                    const DropdownMenuItem(
                      value: 'group',
                      child: Text('Grupo'),
                    ),
                    const DropdownMenuItem(
                      value: 'student',
                      child: Text('Estudiante'),
                    ),
                  ],
                  const DropdownMenuItem(
                    value: 'user',
                    child: Text('Usuario específico: padre o alumno'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _scope = v!;
                  _target = null;
                }),
              ),
              const SizedBox(height: 12),
              if (_scope == 'role')
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: const [
                    DropdownMenuItem(value: 'parent', child: Text('Padres')),
                    DropdownMenuItem(value: 'student', child: Text('Alumnos')),
                  ],
                  onChanged: (v) => setState(() => _role = v!),
                ),
              if (['group', 'student', 'user'].contains(_scope))
                TextFormField(
                  key: ValueKey((_scope, _target)),
                  initialValue: _lookup(rows, _target),
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Seleccionar destinatario',
                    hintText: 'Buscar por nombre',
                    suffixIcon: Icon(Icons.search_rounded),
                  ),
                  onTap: () async {
                    final target = await showDialog<int>(
                        context: context,
                        builder: (_) => _RecipientSearchDialog(
                            rows: rows, selected: _target,),);
                    if (target != null && mounted) {
                      setState(() => _target = target);
                    }
                  },
                ),
              if (!widget.visibility) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _permission,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Permiso'),
                  items: [
                    for (final entry in portalPermissionLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (v) => setState(() => _permission = v!),
                ),
              ],
              if (widget.visibility) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _period,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Periodo / trimestre'),
                  items: [
                    const DropdownMenuItem<int>(
                      child: Text('Todos los periodos'),
                    ),
                    for (final row in widget.config['periods'] as List)
                      DropdownMenuItem(
                        value: row['id'] as int,
                        child: Text(row['name'] as String),
                      ),
                  ],
                  onChanged: (v) => setState(() => _period = v),
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.visibility
                      ? (_allowed ? 'Notas visibles' : 'Notas ocultas')
                      : (_allowed
                          ? 'Acceso habilitado'
                          : 'Acceso deshabilitado'),
                ),
                value: _allowed,
                onChanged: (v) => setState(() => _allowed = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed:
              ['group', 'student', 'user'].contains(_scope) && _target == null
                  ? null
                  : () => Navigator.pop(context, {
                        'action': widget.visibility
                            ? 'save_visibility'
                            : 'save_permission',
                        'scope': _scope,
                        'allowed': _allowed,
                        if (_scope == 'role') 'role': _role,
                        if (_scope == 'user') 'userId': _target,
                        if (_scope == 'group') 'groupId': _target,
                        if (_scope == 'student') 'studentId': _target,
                        if (widget.visibility) 'periodId': _period,
                        if (!widget.visibility) 'permission': _permission,
                      }),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

String _searchKey(String value) => value
    .toLowerCase()
    .trim()
    .replaceAll(RegExp('[áàäâ]'), 'a')
    .replaceAll(RegExp('[éèëê]'), 'e')
    .replaceAll(RegExp('[íìïî]'), 'i')
    .replaceAll(RegExp('[óòöô]'), 'o')
    .replaceAll(RegExp('[úùüû]'), 'u')
    .replaceAll('ñ', 'n');

class _RecipientSearchDialog extends StatefulWidget {
  const _RecipientSearchDialog({required this.rows, this.selected});
  final List<dynamic> rows;
  final int? selected;
  @override
  State<_RecipientSearchDialog> createState() => _RecipientSearchDialogState();
}

class _RecipientSearchDialogState extends State<_RecipientSearchDialog> {
  String _query = '';
  late final _indexed = [
    for (final row in widget.rows)
      (
        row: row as Map<String, dynamic>,
        key: _searchKey('${row['name']} ${row['id']}')
      ),
  ];
  @override
  Widget build(BuildContext context) {
    final terms = _searchKey(_query)
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    final matches =
        _indexed.where((item) => terms.every(item.key.contains)).toList();
    final shown = matches.take(50).toList();
    return AlertDialog(
      title: const Text('Buscar destinatario'),
      content: SizedBox(
          width: 460,
          height: 420,
          child: Column(children: [
            TextField(
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Nombre del destinatario',
                    hintText: 'Escribe para buscar…',
                    prefixIcon: Icon(Icons.search_rounded),),
                onChanged: (value) => setState(() => _query = value),),
            const SizedBox(height: 8),
            Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    matches.length > shown.length
                        ? 'Mostrando ${shown.length} de ${matches.length}. Escribe para filtrar.'
                        : '${matches.length} ${matches.length == 1 ? 'resultado' : 'resultados'}',
                    style: context.textTheme.bodySmall,),),
            const SizedBox(height: 8),
            Expanded(
                child: shown.isEmpty
                    ? const Center(
                        child: Text('Sin coincidencias. Prueba otro nombre.'),)
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final row = shown[index].row;
                          return ListTile(
                              title: Text(row['name'] as String),
                              trailing: row['id'] == widget.selected
                                  ? const Icon(Icons.check_rounded)
                                  : null,
                              onTap: () =>
                                  Navigator.pop(context, row['id'] as int),);
                        },),),
          ],),),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),),
      ],
    );
  }
}
