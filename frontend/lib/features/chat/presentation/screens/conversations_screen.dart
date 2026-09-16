import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/educa_fab.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
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

    return StudentDetailScaffold(
      title: 'Mensajes',
      showBack: false,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      fab: EducaFab(
        icon: Icons.chat_bubble_outline,
        onPressed: () => context.push(Routes.chatNew),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
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
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
              ),
            ),
            Expanded(
              child: conversations.when(
                loading: () => const SkeletonList(),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (list) {
                  final filtered = _query.isEmpty
                      ? list
                      : list.where((c) =>
                          c.title.toLowerCase().contains(_query) ||
                          (c.lastMessage?.content
                                  ?.toLowerCase()
                                  .contains(_query) ??
                              false),).toList();
                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.forum_rounded,
                      title: _query.isEmpty
                          ? 'Sin conversaciones'
                          : 'Sin coincidencias',
                      subtitle: _query.isEmpty
                          ? 'Toca el botón + para iniciar una.'
                          : 'Intenta con otro término.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
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
