import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../providers.dart';

class NewConversationScreen extends ConsumerStatefulWidget {
  const NewConversationScreen({super.key});

  @override
  ConsumerState<NewConversationScreen> createState() =>
      _NewConversationScreenState();
}

class _NewConversationScreenState
    extends ConsumerState<NewConversationScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final contactsAsync = ref.watch(discoverableContactsProvider(_query));

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Nuevo mensaje'),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o rol…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: contactsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (contacts) {
                  if (contacts.isEmpty) {
                    return const EmptyState(
                      icon: Icons.search_off,
                      title: 'Sin resultados',
                      subtitle: 'Intenta con otro término.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: contacts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c = contacts[i];
                      return EduCard(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          leading: UserAvatar(name: c.name, size: 40),
                          title: Text(c.name,
                              style: context.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          subtitle: Text(_roleLabel(c.role),
                              style: context.textTheme.bodySmall),
                          trailing: Icon(Icons.chat_bubble_outline,
                              color: palette.limeDeep),
                          onTap: () async {
                            final repo = ref.read(chatRepositoryProvider);
                            final conv = await repo.ensureIndividual(
                              otherUserId: c.userId,
                              otherName: c.name,
                              otherRole: c.role,
                              otherAvatarUrl: c.avatarUrl,
                            );
                            if (!context.mounted) return;
                            context.pushReplacement(
                              '${Routes.chat}/${conv.id}',
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String code) => switch (code) {
        'teacher' => 'Maestro',
        'parent' => 'Padre/Tutor',
        'student' => 'Estudiante',
        'admin' => 'Administrador',
        'coordinator' => 'Coordinador',
        'director' => 'Director',
        _ => code,
      };
}
