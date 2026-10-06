import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
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

    return StudentDetailScaffold(
      title: unread > 0 ? 'Alertas ($unread)' : 'Alertas',
      showBack: false,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _FilterBar(
              selected: _filter,
              onSelect: (v) => setState(() => _filter = v),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      unread > 0
                          ? '$unread sin leer'
                          : 'Todo al día',
                      style: context.textTheme.labelMedium?.copyWith(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
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
                        Icon(Icons.mark_email_read_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Marcar todas leídas'),
                      ],),
                    ),
                    PopupMenuItem(
                      value: 'clear',
                      child: Row(children: [
                        Icon(Icons.delete_sweep_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Vaciar bandeja'),
                      ],),
                    ),
                    PopupMenuItem(
                      value: 'simulate',
                      child: Row(children: [
                        Icon(Icons.notifications_active_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Simular una (demo)'),
                      ],),
                    ),
                  ],
                ),
                ],
              ),
            ),
            Expanded(
              child: feed.when(
                loading: () =>
                    const SkeletonList(),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (items) {
                  final filtered = _filter == null
                      ? items
                      : items.where((n) => n.channel == _filter).toList();
                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.notifications_off_rounded,
                      title: _filter == null
                          ? 'Sin alertas'
                          : 'Sin alertas de ${_filter!.title}',
                      subtitle:
                          'Tus notificaciones aparecerán aquí en tiempo real.',
                    );
                  }
                  return RefreshIndicator(
                    color: palette.accentDeep,
                    onRefresh: () async =>
                        ref.invalidate(notificationsFeedProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
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
                                borderRadius: BorderRadius.circular(Radii.md),
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
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) {
          final f = (20 / r.width).clamp(0.0, 0.5);
          return LinearGradient(
            colors: const [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0, f, 1 - f, 1],
          ).createShader(r);
        },
        child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        children: [
          _Chip(
            label: 'Todas',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final ch in NotificationChannel.values.where(
              (c) => c != NotificationChannel.system,))
            _Chip(
              label: ch.title,
              icon: ch.icon,
              selected: selected == ch,
              onTap: () => onSelect(ch),
            ),
        ],
      ),
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
    return BrutalPill(
      compact: true,
      label: label,
      icon: icon,
      selected: selected,
      onTap: onTap,
    );
  }
}
