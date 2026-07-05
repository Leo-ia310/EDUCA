import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities.dart';
import 'conversation_avatar.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.currentUserId,
    this.onTap,
  });

  final Conversation conversation;
  final String currentUserId;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final last = conversation.lastMessage;
    final unread = conversation.unreadCount;
    final isMine = last?.senderId == currentUserId;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ConversationAvatar(conversation: conversation),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.title,
                          style: context.textTheme.titleSmall?.copyWith(
                            fontWeight: unread > 0
                                ? FontWeight.w800
                                : FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (last != null)
                        Text(
                          _relative(last.sentAt),
                          style: context.textTheme.labelSmall?.copyWith(
                            color: unread > 0
                                ? palette.limeDeep
                                : palette.textMuted,
                            fontWeight: unread > 0
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (conversation.typing)
                        Text(
                          'Escribiendo…',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: palette.info,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else if (last != null)
                        Expanded(
                          child: Row(
                            children: [
                              if (isMine)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    _statusIcon(last.status),
                                    size: 14,
                                    color: last.status ==
                                            MessageDeliveryStatus.read
                                        ? palette.info
                                        : palette.textMuted,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  _preview(last),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textTheme.bodySmall?.copyWith(
                                    color: unread > 0
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                        : palette.textMuted,
                                    fontWeight: unread > 0
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (unread > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          constraints: const BoxConstraints(minWidth: 22),
                          decoration: BoxDecoration(
                            color: palette.limeDeep,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                              color: Color(0xFF1E2218),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(MessageDeliveryStatus s) => switch (s) {
        MessageDeliveryStatus.sending => Icons.schedule_rounded,
        MessageDeliveryStatus.sent => Icons.check_rounded,
        MessageDeliveryStatus.delivered => Icons.done_all_rounded,
        MessageDeliveryStatus.read => Icons.done_all_rounded,
        MessageDeliveryStatus.failed => Icons.error_outline_rounded,
      };

  String _preview(Message m) {
    if (m.attachment != null && !m.hasText) {
      return m.attachment!.isImage ? '📷 Imagen' : '📎 ${m.attachment!.name}';
    }
    return m.content ?? '';
  }

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'ahora';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays == 1) return 'ayer';
    if (diff.inDays < 7) return '${diff.inDays} d';
    return DateFormat('d MMM', 'es').format(d);
  }
}
