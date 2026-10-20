import '../../../portal_access/providers.dart';
import '../../../portal_access/access_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../notifications/providers.dart';
import '../../domain/entities.dart';
import '../../providers.dart';
import '../controllers/chat_controller.dart';
import '../controllers/conversation_read_tracker.dart';
import '../widgets/chat_input.dart';
import '../widgets/conversation_avatar.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _scrollCtrl = ScrollController();
  String? _lastMessageId;
  bool _loadingOlder = false;
  String? _lastReadSignature;
  late final ConversationReadTracker _readTracker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readTracker = ConversationReadTracker(
      markRead: () =>
          ref.read(chatRepositoryProvider).markAsRead(widget.conversationId),
      refreshAlerts: () async {
        if (mounted) await ref.read(notificationsRepositoryProvider).refresh();
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _readVisibleMessages());
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _lastReadSignature = null;
      _lastMessageId = null;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _readVisibleMessages());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _lastReadSignature = null;
    ref.invalidate(messagesStreamProvider(widget.conversationId));
    ref.invalidate(conversationsStreamProvider);
  }

  Future<void> _readVisibleMessages() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final messages =
        ref.read(messagesStreamProvider(widget.conversationId)).valueOrNull;
    if (messages == null) return;
    final meId = ref.read(authControllerProvider).user?.id;
    final incomingIds = messages
        .where((m) => m.senderId != meId)
        .map((m) => m.id)
        .toList()
      ..sort();
    final signature = incomingIds.join(',');
    if (signature == _lastReadSignature) return;
    _lastReadSignature = signature;
    try {
      await _readTracker.read();
    } catch (_) {
      _lastReadSignature = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('No se pudo confirmar la lectura de los mensajes.'),
          action: SnackBarAction(
            label: 'Reintentar',
            onPressed: _readVisibleMessages,
          ),
        ),
      );
    }
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

  Future<void> _loadOlder() async {
    if (_loadingOlder) return;
    final previousHeight =
        _scrollCtrl.hasClients ? _scrollCtrl.position.maxScrollExtent : 0.0;
    final previousOffset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    setState(() => _loadingOlder = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .loadOlderMessages(widget.conversationId);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo((previousOffset +
                    _scrollCtrl.position.maxScrollExtent -
                    previousHeight)
                .clamp(0, _scrollCtrl.position.maxScrollExtent),);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo cargar el historial: $e')),);
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).user;
    final messages = ref.watch(messagesStreamProvider(widget.conversationId));
    ref.listen(messagesStreamProvider(widget.conversationId), (_, next) {
      if (next.hasValue && !next.isLoading) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _readVisibleMessages());
      }
    });
    final composer = ref.watch(chatComposerProvider(widget.conversationId));
    final composerCtrl =
        ref.read(chatComposerProvider(widget.conversationId).notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Atrás',
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: _HeaderTitle(conversationId: widget.conversationId),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Información',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (ctx) => SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications_off_rounded),
                      title: const Text('Silenciar conversación'),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Conversación silenciada.'),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.search),
                      title: const Text('Buscar en la conversación'),
                      onTap: () => Navigator.of(ctx).pop(),
                    ),
                    ListTile(
                      leading: const Icon(Icons.report_gmailerrorred_rounded),
                      title: const Text('Reportar'),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Reporte enviado a coordinación.'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (ref
              .read(chatRepositoryProvider)
              .hasOlderMessages(widget.conversationId))
            TextButton(
                onPressed: _loadingOlder ? null : _loadOlder,
                child: Text(_loadingOlder
                    ? 'Cargando…'
                    : 'Cargar mensajes anteriores',),),
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorStateView(message: '$e'),
              data: (list) {
                final ordered = [...list]..sort((a, b) {
                    final byDate = a.sentAt.compareTo(b.sentAt);
                    if (byDate != 0) return byDate;
                    final aId = BigInt.tryParse(a.id), bId = BigInt.tryParse(b.id);
                    return aId != null && bId != null ? aId.compareTo(bId) : a.id.compareTo(b.id);
                  });
                if (ordered.isNotEmpty && ordered.last.id != _lastMessageId) {
                  _lastMessageId = ordered.last.id;
                  _scrollToBottom();
                }
                if (ordered.isEmpty) {
                  return const EmptyState(
                    icon: Icons.forum_rounded,
                    title: 'Empieza la conversación',
                    subtitle: 'Envía el primer mensaje.',
                  );
                }
                return _MessagesList(
                  scrollCtrl: _scrollCtrl,
                  messages: ordered,
                  meId: me?.id ?? '',
                );
              },
            ),
          ),
          if (!ref.watch(portalCanProvider('messages.send')))
            const PortalRestriction(
                message:
                    'Tu institución ha deshabilitado el envío de mensajes. Puedes seguir leyendo la conversación.',)
          else
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
    final convs = ref.watch(conversationDetailProvider(conversationId));
    return convs.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (conv) {
        if (conv == null) return const SizedBox.shrink();
        final subtitle = conv.typing
            ? 'Escribiendo…'
            : (conv.kind == ConversationKind.group
                ? '${conv.participants.length} miembros'
                : (conv.counterpart?.isOnline == true
                    ? 'En línea'
                    : _activitySubtitle(conv)));
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

  String _activitySubtitle(Conversation conv) {
    final lastSeen = conv.counterpart?.lastSeen;
    if (lastSeen != null) return 'Última vez ${_relative(lastSeen)}';
    final lastMessageAt = conv.lastMessage?.sentAt;
    if (lastMessageAt != null) {
      return 'Último mensaje ${_relative(lastMessageAt)}';
    }
    return 'Sin mensajes recientes';
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
            borderRadius: BorderRadius.circular(Radii.pill),
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
