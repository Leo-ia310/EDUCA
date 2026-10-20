import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/educa_fab.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../portal_access/providers.dart';
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
  Timer? _searchDebounce;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search('');
    });
  }

  void _search(String value) {
    setState(() => _query = value.trim().toLowerCase());
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        await ref.read(chatRepositoryProvider).searchConversations(value);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('No se pudo buscar: $e')));
        }
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      await ref.read(chatRepositoryProvider).loadMoreConversations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo cargar: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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
      fab: ref.watch(portalCanProvider('messages.send'))
          ? EducaFab(
              icon: Icons.chat_bubble_outline,
              onPressed: () => context.push(Routes.chatNew),
            )
          : null,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: 'Buscar conversación…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    borderSide: BorderSide(
                      color: Brutal.ink(context),
                      width: Brutal.border,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    borderSide: BorderSide(
                      color: Brutal.ink(context),
                      width: Brutal.border,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: conversations.when(
                loading: () => const SkeletonList(),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (list) {
                  final filtered = list;
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
                    itemCount: filtered.length +
                        (ref.read(chatRepositoryProvider).hasMoreConversations
                            ? 1
                            : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => i == filtered.length
                        ? TextButton(
                            onPressed: _loadingMore ? null : _loadMore,
                            child: Text(_loadingMore
                                ? 'Cargando…'
                                : 'Cargar más conversaciones',),)
                        : ConversationTile(
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
