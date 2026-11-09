import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/backend_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/subject_palette.dart';
import '../../core/widgets/user_avatar.dart';
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
          const SnackBar(content: Text('Colaboración actualizada.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo actualizar la colaboración. $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(
    Map<String, dynamic> workspace, {
    Map<String, dynamic>? invitation,
  }) async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _InviteDialog(
        workspace: workspace,
        invitation: invitation,
        initialClassId: widget.initialClassId,
      ),
    );
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
          onRetry: () => ref.invalidate(collaborationWorkspaceProvider),
        ),
        data: (data) {
          final palette = context.palette;
          final classes = (data['classes'] as List)
              .where((c) => c['isOwner'] == true)
              .toList();
          final invitations =
              (data['invitations'] as List).cast<Map<String, dynamic>>();
          bool is_(Map<String, dynamic> i, String status) =>
              i['status'] == status;
          final pendingIn = [
            for (final i in invitations)
              if (i['incoming'] == true && is_(i, 'pending')) i,
          ];
          final active = [
            for (final i in invitations)
              if (is_(i, 'active')) i,
          ];
          final waiting = [
            for (final i in invitations)
              if (i['incoming'] != true && is_(i, 'pending')) i,
          ];
          final history = [
            for (final i in invitations)
              if (is_(i, 'declined') || is_(i, 'revoked')) i,
          ];

          Widget section(
            String title,
            IconData icon,
            List<Map<String, dynamic>> items, {
            String? hint,
          }) {
            if (items.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
                  child: Row(
                    children: [
                      Icon(icon, size: 18, color: palette.accentDeep),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: context.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.accentSoft,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(
                          '${items.length}',
                          style: context.textTheme.labelSmall?.copyWith(
                            color: palette.accentDeep,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
                    child: Text(
                      hint,
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: palette.textMuted),
                    ),
                  ),
                for (final i in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _InvitationCard(
                      invitation: i,
                      saving: _saving,
                      onManage: _manage,
                      onEdit: () => _edit(data, invitation: i),
                    ),
                  ),
                const SizedBox(height: 4),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DepthCard(
                soft: true,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: palette.accentSoft,
                            borderRadius: BorderRadius.circular(Radii.md),
                          ),
                          child: Icon(
                            Icons.group_add_rounded,
                            color: palette.accentDeep,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Comparte tus clases con otros profesores',
                            style: context.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'El acceso empieza cuando aceptan la invitación, y tú decides qué pueden hacer en cada clase.',
                      style: context.textTheme.bodyMedium
                          ?.copyWith(color: palette.textMuted),
                    ),
                    if (classes.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _saving ? null : () => _edit(data),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 46),
                        ),
                        icon: const Icon(Icons.person_add_rounded),
                        label: const Text('Invitar profesor'),
                      ),
                    ],
                    if (invitations.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _Count(
                            '${active.length}',
                            'Activas',
                            palette.success,
                          ),
                          _Count(
                            '${pendingIn.length + waiting.length}',
                            'Pendientes',
                            palette.warning,
                          ),
                          _Count(
                            '${history.length}',
                            'Cerradas',
                            palette.textMuted,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 12),
              if (invitations.isEmpty)
                const EmptyState(
                  icon: Icons.group_outlined,
                  title: 'Sin colaboraciones',
                  subtitle:
                      'Aquí aparecerán las invitaciones enviadas y recibidas.',
                ),
              section(
                'Por responder',
                Icons.mark_email_unread_rounded,
                pendingIn,
                hint: 'Otros profesores te invitaron a colaborar en su clase.',
              ),
              section(
                'Colaboraciones activas',
                Icons.handshake_rounded,
                active,
              ),
              section(
                'Esperando respuesta',
                Icons.hourglass_top_rounded,
                waiting,
              ),
              section('Historial', Icons.history_rounded, history),
            ],
          );
        },
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: context.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, color: color),
          ),
          Text(
            label,
            style: context.textTheme.labelSmall
                ?.copyWith(color: context.palette.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de una invitación: clase, persona, estado, permisos y acciones.
class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.saving,
    required this.onManage,
    required this.onEdit,
  });

  final Map<String, dynamic> invitation;
  final bool saving;
  final Future<void> Function(Map<String, dynamic>) onManage;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final i = invitation;
    final incoming = i['incoming'] == true;
    final status = i['status'] as String? ?? '';
    final subject = '${i['subjectName'] ?? 'Clase'}';
    final s = context.pastel(subjectColor(subject));
    final person =
        '${incoming ? i['inviterName'] : i['teacherName'] ?? 'Profesor'}';
    final permissions = (i['permissions'] as List? ?? const []).cast<Object>();
    final readOnly = permissions.every(
      (p) => const {'class.view', 'students.view', 'assignments.review'}
          .contains(p),
    );
    final (statusColor, statusIcon) = switch (status) {
      'active' => (palette.success, Icons.check_circle_rounded),
      'pending' => (palette.warning, Icons.hourglass_top_rounded),
      'declined' => (palette.textMuted, Icons.cancel_rounded),
      'revoked' => (palette.danger, Icons.block_rounded),
      _ => (palette.textMuted, Icons.info_rounded),
    };
    final canManage =
        i['canManage'] == true && (status == 'pending' || status == 'active');

    Widget chip(String text, Color color, {IconData? icon}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 4),
              ],
              Text(
                text,
                style: context.textTheme.labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        );

    return DepthCard(
      soft: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: s.vivid,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${i['groupName'] ?? ''}',
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
              ),
              chip(_shortStatus(status), statusColor, icon: statusIcon),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              UserAvatar(name: person, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      incoming ? 'Te invitó' : 'Invitado por ti',
                      style: context.textTheme.labelSmall
                          ?.copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
              ),
              chip(
                readOnly ? 'Solo lectura' : '${permissions.length} permisos',
                palette.accentDeep,
                icon: readOnly
                    ? Icons.visibility_rounded
                    : Icons.edit_note_rounded,
              ),
            ],
          ),
          if (permissions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in permissions)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Text(
                      collaborationPermissions['$p'] ?? '$p',
                      style: context.textTheme.labelSmall
                          ?.copyWith(color: palette.textMuted),
                    ),
                  ),
              ],
            ),
          ],
          if (incoming && status == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: saving
                        ? null
                        : () => onManage({
                              'action': 'accept',
                              'invitationId': i['id'],
                            }),
                    child: const Text('Aceptar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: saving
                        ? null
                        : () => onManage({
                              'action': 'decline',
                              'invitationId': i['id'],
                            }),
                    child: const Text('Rechazar'),
                  ),
                ),
              ],
            ),
          ],
          if (canManage) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: saving ? null : onEdit,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Editar permisos'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: saving
                        ? null
                        : () => onManage({
                              'action': 'revoke',
                              'invitationId': i['id'],
                            }),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.danger,
                    ),
                    child: const Text('Revocar acceso'),
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

String _shortStatus(String status) => switch (status) {
      'pending' => 'Pendiente',
      'active' => 'Activa',
      'declined' => 'Rechazada',
      'revoked' => 'Revocada',
      _ => status,
    };

class _InviteDialog extends StatefulWidget {
  const _InviteDialog({
    required this.workspace,
    this.invitation,
    this.initialClassId,
  });
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
                        child: Text(t['name'] as String),
                      ),
                  ],
                  onChanged: (v) => setState(() => _teacher = v),
                ),
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
                    }),
                  ),
              ],
              const Divider(),
              Text('Permisos', style: context.textTheme.titleSmall),
              TextButton(
                onPressed: () => setState(
                  () => _permissions = {
                    'class.view',
                    'students.view',
                    'assignments.review',
                  },
                ),
                child: const Text('Solo lectura'),
              ),
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
                            _permissions = normalizeClassPermissions(selected);
                          }),
                ),
              const Text(
                'Revisar, calificar, poner notas y registrar asistencia también habilitan ver los estudiantes de esas clases.',
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
          child: Text(editing ? 'Guardar permisos' : 'Enviar invitación'),
        ),
      ],
    );
  }
}
