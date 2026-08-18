import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/educa_fab.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../providers.dart';
import '../widgets/conversation_tile.dart';

class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsStreamProvider);
    final me = ref.watch(authControllerProvider).user;

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Mensajes'),
      ),
      fab: EducaFab(
        icon: Icons.chat_bubble_outline,
        onPressed: () => context.push(Routes.chatNew),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Buscar conversación…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: conversations.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (list) {
                  final filtered = _query.isEmpty
                      ? list
                      : list.where((c) =>
                          c.title.toLowerCase().contains(_query) ||
                          (c.lastMessage?.content
                                  ?.toLowerCase()
                                  .contains(_query) ??
                              false)).toList();
                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.forum_outlined,
                      title: _query.isEmpty
                          ? 'Sin conversaciones'
                          : 'Sin coincidencias',
                      subtitle: _query.isEmpty
                          ? 'Toca el botón + para iniciar una.'
                          : 'Intenta con otro término.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.5),
                    ),
                    itemBuilder: (_, i) => ConversationTile(
                      conversation: filtered[i],
                      currentUserId: me?.id ?? '',
                      onTap: () => context.push(
                        '${Routes.chat}/${filtered[i].id}',
                      ),
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
