import '../auth/presentation/query_auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/backend_api_client.dart';
import '../../core/network/supabase_client.dart';
import 'data/mock_chat_repository.dart';
import 'data/supabase_chat_repository.dart';
import 'domain/chat_repository.dart';
import 'domain/entities.dart';

/// Repository singleton (para que las conversaciones y su historial se
/// mantengan mientras la app esté abierta).
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final auth = ref.watch(queryAuthProvider);
  final user = auth.user;
  final client = ref.watch(supabaseClientProvider);
  final api = ref.watch(backendApiClientProvider);
  if (user == null) {
    final repository = MockChatRepository(
      meId: 'demo',
      myName: 'Invitado',
      myRoleCode: 'student',
    );
    ref.onDispose(repository.dispose);
    return repository;
  }
  if (client == null || api == null || auth.institution == null) {
    final repository = MockChatRepository(
      meId: user.id,
      myName: user.fullName,
      myRoleCode: user.activeRole.code,
    );
    ref.onDispose(repository.dispose);
    return repository;
  }
  final repository = SupabaseChatRepository(
    client: client,
    api: api,
    meUserId: user.id,
    myName: user.fullName,
    institutionId: auth.institution!.id,
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// Lista viva de conversaciones del usuario actual.
final conversationsStreamProvider = StreamProvider<List<Conversation>>((ref) {
  return ref.watch(chatRepositoryProvider).watchConversations();
});

final conversationDetailProvider = FutureProvider.autoDispose.family<Conversation?, String>((ref, id) async {
  final repository = ref.watch(chatRepositoryProvider);
  final cached = ref.watch(conversationsStreamProvider).valueOrNull?.where((c) => c.id == id).firstOrNull;
  return cached ?? await repository.conversationById(id);
});

/// Mensajes de una conversación puntual.
final messagesStreamProvider = StreamProvider.autoDispose
    .family<List<Message>, String>((ref, conversationId) {
  return ref.watch(chatRepositoryProvider).watchMessages(conversationId);
});

/// Contador global de mensajes sin leer (badge de la bottom nav).
final totalUnreadProvider = StreamProvider<int>((ref) {
  return ref.watch(chatRepositoryProvider).watchTotalUnread();
});

/// Búsqueda de contactos para iniciar chat.
final discoverableContactsProvider = FutureProvider.autoDispose
    .family<List<ChatParticipant>, String>((ref, query) {
  return ref.watch(chatRepositoryProvider).discoverableContacts(query: query);
});
