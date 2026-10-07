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
      bottomNav: false,
      scrollable: false,
      topActions: [
        _MenuButton(
          onSelected: (v) async {
            final repo = ref.read(notificationsRepositoryProvider);
            switch (v) {
              case 'read_all':
                await repo.markAllRead();
              case 'clear':
                await repo.clearAll();
              case 'simulate':
                await simulateDemoNotification(ref, channel: _filter);
            }
          },
        ),
      ],
      bodyPadding: EdgeInsets.zero,
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
                loading: () => const SkeletonList(),
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

class _FilterBar extends StatefulWidget {
  const _FilterBar({required this.selected, required this.onSelect});
  final NotificationChannel? selected;
  final ValueChanged<NotificationChannel?> onSelect;

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  final _controller = ScrollController();
  bool _fadeLeft = false;
  bool _fadeRight = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    final p = _controller.position;
    final left = p.pixels > 2;
    final right = p.pixels < p.maxScrollExtent - 2;
    if (left != _fadeLeft || right != _fadeRight) {
      setState(() {
        _fadeLeft = left;
        _fadeRight = right;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        // Las píldoras se desvanecen suavemente: invisibles a 12 px del borde
        // y totalmente visibles a ~64 px, solo del lado hacia donde hay más.
        shaderCallback: (r) {
          final a = (12 / r.width).clamp(0.0, 0.2);
          final b = (64 / r.width).clamp(0.0, 0.45);
          return LinearGradient(
            colors: [
              _fadeLeft ? Colors.transparent : Colors.black,
              _fadeLeft ? Colors.transparent : Colors.black,
              Colors.black,
              Colors.black,
              _fadeRight ? Colors.transparent : Colors.black,
              _fadeRight ? Colors.transparent : Colors.black,
            ],
            stops: [0, a, b, 1 - b, 1 - a, 1],
          ).createShader(r);
        },
        child: ListView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          children: [
            _Chip(
              label: 'Todas',
              selected: widget.selected == null,
              onTap: () => widget.onSelect(null),
            ),
            for (final ch in NotificationChannel.values
                .where((c) => c != NotificationChannel.system))
              _Chip(
                label: ch.title,
                icon: ch.icon,
                selected: widget.selected == ch,
                onTap: () => widget.onSelect(ch),
              ),
          ],
        ),
      ),
    );
  }
}

/// Menú de tres puntos de la barra superior (estilo del resto de botones).
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onSelected});
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Opciones',
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'read_all',
          child: Row(
            children: [
              Icon(Icons.mark_email_read_rounded, size: 18),
              SizedBox(width: 8),
              Text('Marcar todas leídas'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'clear',
          child: Row(
            children: [
              Icon(Icons.delete_sweep_rounded, size: 18),
              SizedBox(width: 8),
              Text('Vaciar bandeja'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'simulate',
          child: Row(
            children: [
              Icon(Icons.notifications_active_rounded, size: 18),
              SizedBox(width: 8),
              Text('Simular una (demo)'),
            ],
          ),
        ),
      ],
      child: Container(
        width: 42,
        height: 42,
        margin: const EdgeInsets.only(right: 3, bottom: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(3, 3)),
          ],
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          color: Colors.black,
          size: 24,
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
