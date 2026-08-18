import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.showSender = false,
    this.groupWithPrevious = false,
  });

  final Message message;
  final bool isMine;
  final bool showSender;
  final bool groupWithPrevious;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bg = isMine ? palette.limeDeep : palette.cardElevated;
    final fg = isMine ? const Color(0xFF1E2218) : Theme.of(context).colorScheme.onSurface;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final topRadius = groupWithPrevious ? 6.0 : 18.0;

    return Padding(
      padding: EdgeInsets.only(
        top: groupWithPrevious ? 2 : 8,
        bottom: 0,
        left: isMine ? 60 : 0,
        right: isMine ? 0 : 60,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (showSender && !isMine) ...[
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Text(
                message.senderName,
                style: context.textTheme.labelSmall?.copyWith(
                  color: palette.limeDeep,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          Container(
            padding: message.attachment != null && message.attachment!.isImage
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isMine ? 18 : topRadius),
                topRight: Radius.circular(isMine ? topRadius : 18),
                bottomLeft: Radius.circular(isMine ? 18 : 6),
                bottomRight: Radius.circular(isMine ? 6 : 18),
              ),
              border: !isMine
                  ? Border.all(color: Theme.of(context).dividerColor)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.attachment != null) _AttachmentBlock(
                    attachment: message.attachment!, isMine: isMine),
                if (message.hasText)
                  Padding(
                    padding: message.attachment != null
                        ? const EdgeInsets.fromLTRB(12, 8, 12, 4)
                        : EdgeInsets.zero,
                    child: Text(
                      message.content!,
                      style:
                          context.textTheme.bodyMedium?.copyWith(color: fg),
                    ),
                  ),
                Padding(
                  padding: message.attachment != null && !message.hasText
                      ? const EdgeInsets.only(right: 12, bottom: 8)
                      : EdgeInsets.zero,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('HH:mm').format(message.sentAt),
                        style: context.textTheme.labelSmall?.copyWith(
                          color: (isMine
                                  ? const Color(0xFF1E2218)
                                  : palette.textMuted)
                              .withValues(alpha: 0.7),
                          fontSize: 10,
                        ),
                      ),
                      if (isMine) ...[
                        const SizedBox(width: 4),
                        Icon(
                          _statusIcon(message.status),
                          size: 12,
                          color: _statusColor(message.status, palette),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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

  Color _statusColor(MessageDeliveryStatus s, AppPalette palette) =>
      switch (s) {
        MessageDeliveryStatus.read => palette.info,
        MessageDeliveryStatus.failed => palette.danger,
        _ => const Color(0xFF1E2218),
      };
}

class _AttachmentBlock extends StatelessWidget {
  const _AttachmentBlock({required this.attachment, required this.isMine});
  final MessageAttachment attachment;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (attachment.isImage) {
      return ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
        ),
        child: Container(
          width: 220,
          height: 160,
          color: palette.surfaceAlt,
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined, size: 42),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (isMine ? Colors.white : palette.limeSoft)
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.description_outlined,
              size: 18,
              color: isMine ? const Color(0xFF1E2218) : palette.limeDeep,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isMine ? const Color(0xFF1E2218) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
