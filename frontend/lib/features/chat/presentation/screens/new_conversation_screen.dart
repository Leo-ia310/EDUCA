import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../domain/entities.dart';
import '../../providers.dart';

class NewConversationScreen extends ConsumerStatefulWidget {
  const NewConversationScreen({super.key});

  @override
  ConsumerState<NewConversationScreen> createState() =>
      _NewConversationScreenState();
}

class _NewConversationScreenState extends ConsumerState<NewConversationScreen> {
  final _messageCtrl = TextEditingController();
  String _query = '';
  ChatParticipant? _selected;
  bool _sending = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendInitialMessage() async {
    final selected = _selected;
    final text = _messageCtrl.text.trim();
    if (selected == null) {
      _showSnack('Selecciona un destinatario.');
      return;
    }
    if (text.isEmpty) {
      _showSnack('Escribe el primer mensaje.');
      return;
    }
    setState(() => _sending = true);
    try {
      final repo = ref.read(chatRepositoryProvider);
      final conv = await repo.ensureIndividual(
        otherUserId: selected.userId,
        otherName: selected.name,
        otherRole: selected.role,
        otherAvatarUrl: selected.avatarUrl,
      );
      await repo.sendMessage(conversationId: conv.id, content: text);
      ref.invalidate(conversationsStreamProvider);
      if (!mounted) return;
      context.pushReplacement('${Routes.chat}/${conv.id}');
    } catch (e) {
      if (!mounted) return;
      _showSnack('No se pudo iniciar la conversación: $e');
      setState(() => _sending = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final contactsAsync = ref.watch(discoverableContactsProvider(_query));
    final canSend =
        _selected != null && _messageCtrl.text.trim().isNotEmpty && !_sending;

    return StudentDetailScaffold(
      title: 'Nuevo mensaje',
      scrollable: false,
      bottomNav: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o rol…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
              ),
            ),
            Expanded(
              child: contactsAsync.when(
                loading: () => const SkeletonList(),
                error: (e, _) => Center(child: Text('$e')),
                data: (contacts) {
                  if (contacts.isEmpty) {
                    return const EmptyState(
                      icon: Icons.search_off,
                      title: 'Sin resultados',
                      subtitle: 'Intenta con otro término.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: contacts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c = contacts[i];
                      final selected = _selected?.userId == c.userId;
                      return DepthCard(
                        soft: true,
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          selected: selected,
                          leading: UserAvatar(name: c.name, size: 40),
                          title: Text(
                            c.name,
                            style: context.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            _roleLabel(c.role),
                            style: context.textTheme.bodySmall,
                          ),
                          trailing: Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.chat_bubble_outline,
                            color:
                                selected ? palette.success : palette.accentDeep,
                          ),
                          onTap: () => setState(() => _selected = c),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _InitialMessageComposer(
              selected: _selected,
              controller: _messageCtrl,
              sending: _sending,
              canSend: canSend,
              onChanged: () => setState(() {}),
              onSend: _sendInitialMessage,
              roleLabel: _roleLabel,
            ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String code) => switch (code) {
        'teacher' => 'Maestro',
        'parent' => 'Padre',
        'student' => 'Estudiante',
        'admin' => 'Administrador',
        'coordinator' => 'Coordinador',
        'director' => 'Director',
        'support' => 'Soporte',
        _ => code.isEmpty ? 'Sin rol asignado' : code,
      };
}

class _InitialMessageComposer extends StatelessWidget {
  const _InitialMessageComposer({
    required this.selected,
    required this.controller,
    required this.sending,
    required this.canSend,
    required this.onChanged,
    required this.onSend,
    required this.roleLabel,
  });

  final ChatParticipant? selected;
  final TextEditingController controller;
  final bool sending;
  final bool canSend;
  final VoidCallback onChanged;
  final Future<void> Function() onSend;
  final String Function(String code) roleLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selected == null)
            Text(
              'Selecciona un destinatario para escribirle.',
              style: context.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            )
          else
            Row(
              children: [
                UserAvatar(name: selected!.name, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        roleLabel(selected!.role),
                        style: context.textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !sending,
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    hintText: 'Escribe el primer mensaje…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.lg),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 48,
                height: 48,
                child: FilledButton(
                  onPressed: canSend ? onSend : null,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    backgroundColor: palette.accentDeep,
                  ),
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
