import 'package:equatable/equatable.dart';

/// Tipo de conversación.
enum ConversationKind {
  /// 1:1 entre dos usuarios.
  individual,

  /// Grupal (>2 participantes).
  group,
}

/// Estado de un mensaje en el ciclo de envío.
enum MessageDeliveryStatus {
  /// Aún no confirmado por el servidor (offline / en cola).
  sending,

  /// Recibido por el servidor.
  sent,

  /// Recibido por otros participantes.
  delivered,

  /// Leído por al menos otro participante (o por todos, según UI).
  read,

  /// Falló el envío.
  failed,
}

/// Adjunto de un mensaje (imagen o archivo). Reutiliza la misma abstracción
/// de subida que asignaciones (`FileUploadService`).
class MessageAttachment extends Equatable {
  const MessageAttachment({
    required this.id,
    required this.name,
    required this.url,
    this.sizeBytes,
    this.mimeType,
  });

  final String id;
  final String name;
  final String url;
  final int? sizeBytes;
  final String? mimeType;

  bool get isImage =>
      mimeType?.startsWith('image/') == true ||
      const ['png', 'jpg', 'jpeg', 'webp', 'gif']
          .any((ext) => name.toLowerCase().endsWith(ext));

  @override
  List<Object?> get props => [id, name, url];
}

/// Participante de una conversación. `isMe` se rellena a partir del
/// [AppUser] activo cuando el repositorio arma la lista.
class ChatParticipant extends Equatable {
  const ChatParticipant({
    required this.userId,
    required this.name,
    required this.role,
    this.avatarUrl,
    this.isMe = false,
    this.isOnline = false,
    this.lastSeen,
  });

  final String userId;
  final String name;
  final String role;
  final String? avatarUrl;
  final bool isMe;
  final bool isOnline;
  final DateTime? lastSeen;

  @override
  List<Object?> get props => [userId, name, role, isOnline];
}

/// Vista de conversación para la lista principal.
class Conversation extends Equatable {
  const Conversation({
    required this.id,
    required this.kind,
    required this.title,
    required this.participants,
    required this.updatedAt,
    this.lastMessage,
    this.unreadCount = 0,
    this.avatarUrl,
    this.muted = false,
    this.typing = false,
  });

  final String id;
  final ConversationKind kind;
  final String title;
  final List<ChatParticipant> participants;
  final Message? lastMessage;
  final DateTime updatedAt;
  final int unreadCount;
  final String? avatarUrl;
  final bool muted;
  final bool typing;

  ChatParticipant? get counterpart {
    if (kind != ConversationKind.individual) return null;
    return participants.where((p) => !p.isMe).cast<ChatParticipant?>().firstOrNull;
  }

  Conversation copyWith({
    Message? lastMessage,
    DateTime? updatedAt,
    int? unreadCount,
    List<ChatParticipant>? participants,
    bool? typing,
    String? title,
  }) {
    return Conversation(
      id: id,
      kind: kind,
      title: title ?? this.title,
      participants: participants ?? this.participants,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      avatarUrl: avatarUrl,
      muted: muted,
      typing: typing ?? this.typing,
    );
  }

  @override
  List<Object?> get props =>
      [id, updatedAt, unreadCount, lastMessage, typing];
}

/// Mensaje. `uuid` es la clave estable (usada en offline sync).
class Message extends Equatable {
  const Message({
    required this.id,
    required this.uuid,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.sentAt,
    required this.status,
    this.content,
    this.attachment,
    this.senderAvatarUrl,
    this.replyTo,
    this.editedAt,
  });

  final String id;
  final String uuid;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String? senderAvatarUrl;
  final DateTime sentAt;
  final String? content;
  final MessageAttachment? attachment;
  final Message? replyTo;
  final DateTime? editedAt;
  final MessageDeliveryStatus status;

  bool get hasText => content != null && content!.trim().isNotEmpty;

  Message copyWith({
    MessageDeliveryStatus? status,
    DateTime? editedAt,
    String? content,
  }) {
    return Message(
      id: id,
      uuid: uuid,
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      senderAvatarUrl: senderAvatarUrl,
      sentAt: sentAt,
      content: content ?? this.content,
      attachment: attachment,
      replyTo: replyTo,
      editedAt: editedAt ?? this.editedAt,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props =>
      [uuid, status, editedAt, content];
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
