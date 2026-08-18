import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities.dart';

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    this.onTap,
  });

  final AppNotification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = _channelColor(notification.channel, palette);
    final unread = !notification.read;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: unread ? palette.limeSoft.withValues(alpha: 0.4) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(notification.channel.icon,
                      color: color, size: 20),
                ),
                if (unread)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: palette.danger,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: context.textTheme.titleSmall?.copyWith(
                            fontWeight:
                                unread ? FontWeight.w800 : FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _relative(notification.receivedAt),
                        style: context.textTheme.labelSmall?.copyWith(
                          color: unread ? color : palette.textMuted,
                          fontWeight:
                              unread ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                      fontWeight: unread ? FontWeight.w600 : null,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      notification.channel.title,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _channelColor(NotificationChannel c, AppPalette palette) =>
      switch (c) {
        NotificationChannel.message => palette.info,
        NotificationChannel.task => palette.warning,
        NotificationChannel.grade => palette.success,
        NotificationChannel.attendance => palette.danger,
        NotificationChannel.announcement => palette.limeDeep,
        NotificationChannel.payment => palette.info,
        NotificationChannel.system => palette.textMuted,
      };

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
