import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../domain/entities.dart';
import '../../providers.dart';
import '../controllers/chat_controller.dart';
import '../widgets/chat_input.dart';
import '../widgets/conversation_avatar.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollCtrl = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final me = ref.watch(authControllerProvider).user;
    final messages = ref.watch(messagesStreamProvider(widget.conversationId));
    final composer = ref.watch(chatComposerProvider(widget.conversationId));
    final composerCtrl = ref.read(chatComposerProvider(widget.conversationId).notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: _HeaderTitle(conversationId: widget.conversationId),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorStateView(message: '$e'),
              data: (list) {
                if (list.length != _lastCount) {
                  _lastCount = list.length;
                  _scrollToBottom();
                }
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: palette.limeSoft,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.forum_outlined,
                                color: palette.limeDeep, size: 34),
                          ),
                          const SizedBox(height: 12),
                          Text('Empieza la conversación',
                              style: context.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('Envía el primer mensaje.',
                              style: context.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  );
                }
                return _MessagesList(
                  scrollCtrl: _scrollCtrl,
                  messages: list,
                  meId: me?.id ?? '',
                );
              },
            ),
          ),
          ChatInput(
            onSend: composerCtrl.send,
            onPickAttachment: composerCtrl.pickAttachment,
            pendingAttachment: composer.attachment,
            onRemoveAttachment: composerCtrl.clearAttachment,
            sending: composer.sending || composer.uploading,
          ),
        ],
      ),
    );
  }
}

class _HeaderTitle extends ConsumerWidget {
  const _HeaderTitle({required this.conversationId});
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final convs = ref.watch(conversationsStreamProvider);
    return convs.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        final conv = list.cast<Conversation?>().firstWhere(
              (c) => c?.id == conversationId,
              orElse: () => null,
            );
        if (conv == null) return const SizedBox.shrink();
        final subtitle = conv.typing
            ? 'Escribiendo…'
            : (conv.kind == ConversationKind.group
                ? '${conv.participants.length} miembros'
                : (conv.counterpart?.isOnline == true
                    ? 'En línea'
                    : 'Última vez ${_relative(conv.counterpart?.lastSeen)}'));
        return Row(
          children: [
            ConversationAvatar(conversation: conv, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    conv.title,
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: conv.typing ? palette.info : palette.textMuted,
                      fontWeight: FontWeight.w600,
                      fontStyle: conv.typing ? FontStyle.italic : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _relative(DateTime? d) {
    if (d == null) return '—';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return DateFormat('d MMM HH:mm', 'es').format(d);
  }
}

class _MessagesList extends StatelessWidget {
  const _MessagesList({
    required this.scrollCtrl,
    required this.messages,
    required this.meId,
  });

  final ScrollController scrollCtrl;
  final List<Message> messages;
  final String meId;

  @override
  Widget build(BuildContext context) {
    // Insertar separadores de día.
    final items = <_Item>[];
    DateTime? lastDay;
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final day = DateTime(m.sentAt.year, m.sentAt.month, m.sentAt.day);
      if (lastDay != day) {
        items.add(_Item.day(day));
        lastDay = day;
      }
      final prev = i > 0 ? messages[i - 1] : null;
      final groupWithPrev = prev != null &&
          prev.senderId == m.senderId &&
          m.sentAt.difference(prev.sentAt).inMinutes < 4;
      items.add(_Item.msg(m, groupWithPrev));
    }

    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final it = items[i];
        if (it.day != null) return _DayLabel(day: it.day!);
        final m = it.msg!;
        return MessageBubble(
          message: m,
          isMine: m.senderId == meId,
          showSender: !it.groupWithPrev && m.senderId != meId,
          groupWithPrevious: it.groupWithPrev,
        );
      },
    );
  }
}

class _Item {
  _Item.day(this.day)
      : msg = null,
        groupWithPrev = false;
  _Item.msg(this.msg, this.groupWithPrev) : day = null;

  final DateTime? day;
  final Message? msg;
  final bool groupWithPrev;
}

class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.day});
  final DateTime day;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return 'Hoy';
    if (day == yesterday) return 'Ayer';
    return DateFormat("EEEE d 'de' MMMM", 'es').format(day);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: context.palette.surfaceAlt,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _label(),
            style: context.textTheme.labelSmall?.copyWith(
              color: context.palette.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
