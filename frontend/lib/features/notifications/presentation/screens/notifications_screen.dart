import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../domain/entities.dart';
import '../../domain/notifications_bootstrap.dart';
import '../../providers.dart';
import '../widgets/notification_tile.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  NotificationChannel? _filter;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final feed = ref.watch(notificationsFeedProvider);
    final unread = ref.watch(notificationsUnreadProvider).asData?.value ?? 0;

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(unread > 0 ? 'Alertas ($unread)' : 'Alertas'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) async {
              final repo = ref.read(notificationsRepositoryProvider);
              switch (v) {
                case 'read_all':
                  await repo.markAllRead();
                  break;
                case 'clear':
                  await repo.clearAll();
                  break;
                case 'simulate':
                  await simulateDemoNotification(ref, channel: _filter);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'read_all',
                child: Row(children: [
                  Icon(Icons.mark_email_read_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('Marcar todas leídas'),
                ]),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(children: [
                  Icon(Icons.delete_sweep_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('Vaciar bandeja'),
                ]),
              ),
              PopupMenuItem(
                value: 'simulate',
                child: Row(children: [
                  Icon(Icons.notifications_active_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('Simular una (demo)'),
                ]),
              ),
            ],
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _FilterBar(
              selected: _filter,
              onSelect: (v) => setState(() => _filter = v),
            ),
            Expanded(
              child: feed.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (items) {
                  final filtered = _filter == null
                      ? items
                      : items.where((n) => n.channel == _filter).toList();
                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.notifications_off_outlined,
                      title: _filter == null
                          ? 'Sin alertas'
                          : 'Sin alertas de ${_filter!.title}',
                      subtitle:
                          'Tus notificaciones aparecerán aquí en tiempo real.',
                    );
                  }
                  return RefreshIndicator(
                    color: palette.limeDeep,
                    onRefresh: () async =>
                        ref.invalidate(notificationsFeedProvider),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.5),
                      ),
                      itemBuilder: (_, i) {
                        final n = filtered[i];
                        return Slidable(
                          key: ValueKey(n.id),
                          endActionPane: ActionPane(
                            motion: const BehindMotion(),
                            children: [
                              SlidableAction(
                                onPressed: (_) => ref
                                    .read(notificationsRepositoryProvider)
                                    .remove(n.id),
                                backgroundColor: palette.danger,
                                foregroundColor: Colors.white,
                                icon: Icons.delete_outline,
                                label: 'Eliminar',
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ],
                          ),
                          child: NotificationTile(
                            notification: n,
                            onTap: () async {
                              await ref
                                  .read(notificationsRepositoryProvider)
                                  .markRead(n.id);
                              if (n.deepLink != null && context.mounted) {
                                context.push(n.deepLink!);
                              }
                            },
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelect});
  final NotificationChannel? selected;
  final ValueChanged<NotificationChannel?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _Chip(
            label: 'Todas',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final ch in NotificationChannel.values.where(
              (c) => c != NotificationChannel.system))
            _Chip(
              label: ch.title,
              icon: ch.icon,
              selected: selected == ch,
              onTap: () => onSelect(ch),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? palette.limeDeep : palette.surfaceAlt,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 16,
                    color: selected
                        ? const Color(0xFF1E2218)
                        : palette.textMuted),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: context.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? const Color(0xFF1E2218)
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
