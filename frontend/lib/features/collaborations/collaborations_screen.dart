import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/backend_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/depth_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../assignments/providers.dart';
import '../assignments/presentation/controllers/assignments_list_controller.dart';
import '../attendance/presentation/controllers/attendance_take_controller.dart'
    show todaysClassesProvider;
import '../dashboard/providers.dart';
import '../dashboard/presentation/widgets/student_chrome.dart';
import '../notifications/providers.dart';
import 'providers.dart';

class CollaborationsScreen extends ConsumerStatefulWidget {
  const CollaborationsScreen({super.key, this.initialClassId});
  final int? initialClassId;
  @override
  ConsumerState<CollaborationsScreen> createState() =>
      _CollaborationsScreenState();
}

class _CollaborationsScreenState extends ConsumerState<CollaborationsScreen> {
  bool _saving = false;
  Future<void> _manage(Map<String, dynamic> payload) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final api = ref.read(backendApiClientProvider);
      if (api == null) throw StateError('Las invitaciones requieren conexión.');
      await api.post('/collaborations', data: payload);
      ref.invalidate(collaborationWorkspaceProvider);
      ref.invalidate(teacherDashboardProvider);
      ref.invalidate(teacherClassesProvider);
      ref.invalidate(todaysClassesProvider);
      ref.invalidate(teacherAssignmentsProvider);
      ref.invalidate(notificationsFeedProvider);
      ref.invalidate(notificationsUnreadProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Colaboración actualizada.')),);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo actualizar la colaboración. $error'),),);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> workspace,
      {Map<String, dynamic>? invitation,}) async {
    final payload = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _InviteDialog(
            workspace: workspace,
            invitation: invitation,
            initialClassId: widget.initialClassId,),);
    if (payload != null) await _manage(payload);
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(collaborationWorkspaceProvider);
    return StudentDetailScaffold(
      title: 'Colaboradores',
      bottomNav: false,
      onRefresh: () async {
        ref.invalidate(collaborationWorkspaceProvider);
        await ref.read(collaborationWorkspaceProvider.future);
      },
      child: workspace.when(
          loading: () => const SkeletonList(),
          error: (e, _) => ErrorStateView(
              message: 'No se pudieron cargar las colaboraciones. $e',
              onRetry: () => ref.invalidate(collaborationWorkspaceProvider),),
          data: (data) {
            final classes = (data['classes'] as List)
                .where((c) => c['isOwner'] == true)
                .toList();
            final invitations =
                (data['invitations'] as List).cast<Map<String, dynamic>>();
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Comparte una o varias clases con profesores de tu institución. El acceso empieza cuando aceptan la invitación.',
                      style: context.textTheme.bodyMedium,),
                  const SizedBox(height: 16),
                  if (classes.isNotEmpty)
                    FilledButton.icon(
                        onPressed: _saving ? null : () => _edit(data),
                        icon: const Icon(Icons.person_add_rounded),
                        label: const Text('Invitar profesor'),),
                  if (_saving) const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  if (invitations.isEmpty)
                    const EmptyState(
                        icon: Icons.group_outlined,
                        title: 'Sin colaboraciones',
                        subtitle:
                            'Aquí aparecerán las invitaciones enviadas y recibidas.',),
                  for (final invitation in invitations)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DepthCard(
                            soft: true,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${invitation['subjectName']} · ${invitation['groupName']}',
                                      style: context.textTheme.titleSmall,),
                                  Text(invitation['incoming'] == true
                                      ? 'Invita: ${invitation['inviterName']}'
                                      : 'Profesor: ${invitation['teacherName']}',),
                                  const SizedBox(height: 6),
                                  Text(
                                      _statusLabel(
                                          invitation['status'] as String,),
                                      style: context.textTheme.labelLarge
                                          ?.copyWith(
                                              color: context.palette.accent,),),
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 6, runSpacing: 4, children: [
                                    for (final p
                                        in invitation['permissions'] as List)
                                      Chip(
                                          label: Text(
                                              collaborationPermissions[p] ??
                                                  '$p',),),
                                  ],),
                                  if (invitation['incoming'] == true &&
                                      invitation['status'] == 'pending')
                                    Wrap(spacing: 8, children: [
                                      FilledButton(
                                          onPressed: _saving
                                              ? null
                                              : () => _manage({
                                                    'action': 'accept',
                                                    'invitationId':
                                                        invitation['id'],
                                                  }),
                                          child: const Text('Aceptar'),),
                                      TextButton(
                                          onPressed: _saving
                                              ? null
                                              : () => _manage({
                                                    'action': 'decline',
                                                    'invitationId':
                                                        invitation['id'],
                                                  }),
                                          child: const Text('Rechazar'),),
                                    ],),
                                  if (invitation['canManage'] == true &&
                                      ['pending', 'active']
                                          .contains(invitation['status']))
                                    Wrap(spacing: 8, children: [
                                      TextButton.icon(
                                          onPressed: _saving
                                              ? null
                                              : () => _edit(data,
                                                  invitation: invitation,),
                                          icon: const Icon(Icons.tune_rounded),
                                          label: const Text('Editar permisos'),),
                                      TextButton(
                                          onPressed: _saving
                                              ? null
                                              : () => _manage({
                                                    'action': 'revoke',
                                                    'invitationId':
                                                        invitation['id'],
                                                  }),
                                          child: const Text('Revocar acceso'),),
                                    ],),
                                ],),),),
                ],);
          },),
    );
  }
}

String _statusLabel(String status) => switch (status) {
      'pending' => 'Invitación pendiente',
      'active' => 'Colaboración activa',
      'declined' => 'Invitación rechazada',
      'revoked' => 'Acceso revocado',
      _ => status,
    };

class _InviteDialog extends StatefulWidget {
  const _InviteDialog(
      {required this.workspace, this.invitation, this.initialClassId,});
  final Map<String, dynamic> workspace;
  final Map<String, dynamic>? invitation;
  final int? initialClassId;
  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  int? _teacher;
  final _classes = <int>{};
  Set<String> _permissions = {'class.view'};
  @override
  void initState() {
    super.initState();
    if (widget.initialClassId != null) _classes.add(widget.initialClassId!);
    if (widget.invitation != null) {
      _permissions =
          Set<String>.from(widget.invitation!['permissions'] as List);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.invitation != null;
    return AlertDialog(
      title: Text(editing ? 'Permisos de colaboración' : 'Invitar profesor'),
      content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (!editing) ...[
                  DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: _teacher,
                      decoration: const InputDecoration(labelText: 'Profesor'),
                      items: [
                        for (final t in widget.workspace['teachers'] as List)
                          DropdownMenuItem(
                              value: t['userId'] as int,
                              child: Text(t['name'] as String),),
                      ],
                      onChanged: (v) => setState(() => _teacher = v),),
                  const SizedBox(height: 12),
                  Text('Clases propias', style: context.textTheme.titleSmall),
                  for (final c in (widget.workspace['classes'] as List)
                      .where((c) => c['isOwner'] == true))
                    CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${c['subjectName']} · ${c['groupName']}'),
                        value: _classes.contains(c['classId']),
                        onChanged: (v) => setState(() {
                              if (v == true) {
                                _classes.add(c['classId'] as int);
                              } else {
                                _classes.remove(c['classId']);
                              }
                            }),),
                ],
                const Divider(),
                Text('Permisos', style: context.textTheme.titleSmall),
                TextButton(
                    onPressed: () => setState(() => _permissions = {
                          'class.view',
                          'students.view',
                          'assignments.review',
                        },),
                    child: const Text('Solo lectura'),),
                for (final p in collaborationPermissions.entries)
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.value),
                      value: _permissions.contains(p.key),
                      onChanged: p.key == 'class.view'
                          ? null
                          : (v) => setState(() {
                                final selected = {..._permissions};
                                if (v == true) {
                                  selected.add(p.key);
                                } else {
                                  selected.remove(p.key);
                                }
                                _permissions =
                                    normalizeClassPermissions(selected);
                              }),),
                const Text(
                    'Revisar, calificar, poner notas y registrar asistencia también habilitan ver los estudiantes de esas clases.',),
              ],),),),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),),
        FilledButton(
            onPressed: !editing && (_teacher == null || _classes.isEmpty)
                ? null
                : () => Navigator.pop(context, {
                      'action': editing ? 'update' : 'invite',
                      if (editing) 'invitationId': widget.invitation!['id'],
                      if (!editing) ...{
                        'teacherUserId': _teacher,
                        'classIds': _classes.toList(),
                      },
                      'permissions': _permissions.toList(),
                    }),
            child: Text(editing ? 'Guardar permisos' : 'Enviar invitación'),),
      ],
    );
  }
}
