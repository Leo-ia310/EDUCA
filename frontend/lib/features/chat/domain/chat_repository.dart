import 'entities.dart';

/// Contrato de acceso a conversaciones y mensajes. Es un stream-based repo:
/// [watchConversations] y [watchMessages] devuelven Streams para permitir la
/// integración con Supabase Realtime sin filtrar la abstracción.
abstract class ChatRepository {
  // ---------- Lectura ----------
  /// Lista viva de conversaciones del usuario actual, ordenadas por
  /// `updatedAt` descendente.
  Stream<List<Conversation>> watchConversations();

  bool get hasMoreConversations;
  Future<void> loadMoreConversations();
  Future<void> searchConversations(String query);

  Future<Conversation?> conversationById(String id);

  /// Mensajes de una conversación (histórico + entrantes en tiempo real).
  Stream<List<Message>> watchMessages(String conversationId);

  bool hasOlderMessages(String conversationId);
  Future<void> loadOlderMessages(String conversationId);

  // ---------- Escritura ----------
  /// Envía un mensaje. Devuelve el mensaje ya con `status = sent`. En modo
  /// Si falla conserva su UUID para el reintento explícito del mismo contenido.
  Future<Message> sendMessage({
    required String conversationId,
    String? content,
    MessageAttachment? attachment,
    Message? replyTo,
  });

  /// Marca todos los mensajes no leídos de la conversación como leídos por
  /// el usuario actual.
  Future<void> markAsRead(String conversationId);

  /// Crea una conversación 1:1 con el usuario dado (o devuelve la existente).
  Future<Conversation> ensureIndividual({
    required String otherUserId,
    required String otherName,
    required String otherRole,
    String? otherAvatarUrl,
  });

  /// Cuántos mensajes sin leer tiene el usuario (para badge global).
  Stream<int> watchTotalUnread();

  // ---------- Utilidad ----------
  /// Devuelve algunas personas con las que se puede iniciar una nueva
  /// conversación. En producción se filtra por rol/permiso; en demo son
  /// personajes fijos.
  Future<List<ChatParticipant>> discoverableContacts({String? query});

  /// Notifica al servidor que estamos escribiendo en esta conversación.
  Future<void> setTyping(String conversationId, {required bool typing});
}
