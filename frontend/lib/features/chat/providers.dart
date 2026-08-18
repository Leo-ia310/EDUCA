import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/supabase_client.dart';
import '../auth/presentation/auth_controller.dart';
import 'data/mock_chat_repository.dart';
import 'data/supabase_chat_repository.dart';
import 'domain/chat_repository.dart';
import 'domain/entities.dart';

/// Repository singleton (para que las conversaciones y su historial se
/// mantengan mientras la app esté abierta).
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final user = auth.user;
  final client = ref.watch(supabaseClientProvider);
  if (user == null) {
    return MockChatRepository(
      meId: 'demo',
      myName: 'Invitado',
      myRoleCode: 'student',
    );
  }
  if (client == null || auth.institution == null) {
    return MockChatRepository(
      meId: user.id,
      myName: user.fullName,
      myRoleCode: user.activeRole.code,
    );
  }
  return SupabaseChatRepository(
    client: client,
    meUserId: user.id,
    myName: user.fullName,
    institutionId: auth.institution!.id,
  );
});

/// Lista viva de conversaciones del usuario actual.
final conversationsStreamProvider =
    StreamProvider<List<Conversation>>((ref) {
  return ref.watch(chatRepositoryProvider).watchConversations();
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
