import 'dart:async';

import 'package:uuid/uuid.dart';

import '../domain/chat_repository.dart';
import '../domain/entities.dart';
import 'mock_chat_data.dart';

const _uuid = Uuid();

/// Implementación en memoria + BehaviorSubject-like (usando controllers).
/// Simula respuestas automáticas del contraparte cuando envías un mensaje
/// para que el flujo realtime se sienta orgánico en la demo.
class MockChatRepository implements ChatRepository {
  MockChatRepository({
    required this.meId,
    required this.myName,
    required this.myRoleCode,
  }) {
    _seed();
  }

  final String meId;
  final String myName;
  final String myRoleCode;

  final _conversations = <String, Conversation>{};
  final _messages = <String, List<Message>>{};

  final _conversationsController =
      StreamController<List<Conversation>>.broadcast();
  final _messagesControllers = <String, StreamController<List<Message>>>{};
  final _unreadController = StreamController<int>.broadcast();

  Timer? _autoResponder;

  void _seed() {
    final initial = ChatMockSeed.initialConversations(
      meId: meId,
      myName: myName,
      myRoleCode: myRoleCode,
    );
    for (final c in initial) {
      _conversations[c.id] = c;
      _messages[c.id] = ChatMockSeed.initialMessages(
        conversationId: c.id,
        meId: meId,
        myName: myName,
        participants: c.participants,
        lastMessage: c.lastMessage,
      );
    }
    _emitConversations();
    _emitUnread();
  }

  void _emitConversations() {
    final sorted = _conversations.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (!_conversationsController.isClosed) {
      _conversationsController.add(List.unmodifiable(sorted));
    }
  }

  void _emitMessages(String convId) {
    final list = _messages[convId] ?? const <Message>[];
    final ctrl = _messagesControllers[convId];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(List.unmodifiable(list));
    }
  }

  void _emitUnread() {
    final total =
        _conversations.values.fold<int>(0, (a, c) => a + c.unreadCount);
    if (!_unreadController.isClosed) _unreadController.add(total);
  }

  // ---------- Reads ----------
  @override
  Stream<List<Conversation>> watchConversations() async* {
    yield _conversations.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    yield* _conversationsController.stream;
  }

  @override
  Future<Conversation?> conversationById(String id) async =>
      _conversations[id];

  @override
  Stream<List<Message>> watchMessages(String conversationId) async* {
    final ctrl = _messagesControllers.putIfAbsent(
      conversationId,
      () => StreamController<List<Message>>.broadcast(),
    );
    yield _messages[conversationId] ?? const [];
    yield* ctrl.stream;
  }

  @override
  Stream<int> watchTotalUnread() async* {
    yield _conversations.values.fold<int>(0, (a, c) => a + c.unreadCount);
    yield* _unreadController.stream;
  }

  // ---------- Writes ----------
  @override
  Future<Message> sendMessage({
    required String conversationId,
    String? content,
    MessageAttachment? attachment,
    Message? replyTo,
  }) async {
    final now = DateTime.now();
    final msg = Message(
      id: 'm-${_uuid.v4()}',
      uuid: _uuid.v4(),
      conversationId: conversationId,
      senderId: meId,
      senderName: myName,
      sentAt: now,
      content: content,
      attachment: attachment,
      replyTo: replyTo,
      status: MessageDeliveryStatus.sending,
    );

    _messages.putIfAbsent(conversationId, () => []).add(msg);
    _emitMessages(conversationId);

    // Simular round-trip al server.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _updateStatus(msg, MessageDeliveryStatus.sent);

    // Actualizar conversación.
    final conv = _conversations[conversationId];
    if (conv != null) {
      _conversations[conversationId] = conv.copyWith(
        lastMessage: _messages[conversationId]!.last,
        updatedAt: now,
      );
      _emitConversations();
    }

    // Auto-respuesta: si es 1:1 y no es un grupo, simulamos "typing…" y una
    // respuesta genérica ~2s después. Solo para dar sensación realtime.
    _scheduleAutoReply(conversationId);
    return _messages[conversationId]!.last;
  }

  void _updateStatus(Message msg, MessageDeliveryStatus status) {
    final list = _messages[msg.conversationId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.uuid == msg.uuid);
    if (idx == -1) return;
    list[idx] = list[idx].copyWith(status: status);
    _emitMessages(msg.conversationId);
  }

  void _scheduleAutoReply(String convId) {
    final conv = _conversations[convId];
    if (conv == null) return;
    if (conv.kind != ConversationKind.individual) return;
    final other = conv.counterpart;
    if (other == null) return;

    // Marcar como "typing" en la lista.
    _conversations[convId] = conv.copyWith(typing: true);
    _emitConversations();

    _autoResponder?.cancel();
    _autoResponder = Timer(const Duration(milliseconds: 2200), () {
      final reply = Message(
        id: 'm-${_uuid.v4()}',
        uuid: _uuid.v4(),
        conversationId: convId,
        senderId: other.userId,
        senderName: other.name,
        senderAvatarUrl: other.avatarUrl,
        sentAt: DateTime.now(),
        content: _canonicalReply(other.role),
        status: MessageDeliveryStatus.delivered,
      );
      _messages[convId]!.add(reply);
      _emitMessages(convId);

      final current = _conversations[convId]!;
      _conversations[convId] = current.copyWith(
        lastMessage: reply,
        updatedAt: reply.sentAt,
        typing: false,
        unreadCount: current.unreadCount + 1,
      );
      _emitConversations();
      _emitUnread();
    });
  }

  String _canonicalReply(String role) {
    switch (role) {
      case 'teacher':
        return 'Gracias por escribir, en breve te respondo con más detalle.';
      case 'parent':
        return 'Perfecto profe, muchas gracias por avisar.';
      case 'director':
      case 'coordinator':
        return 'Recibido, coordinamos con el equipo.';
      default:
        return 'Ok, entendido.';
    }
  }

  @override
  Future<void> markAsRead(String conversationId) async {
    final conv = _conversations[conversationId];
    if (conv == null || conv.unreadCount == 0) return;
    _conversations[conversationId] = conv.copyWith(unreadCount: 0);
    final list = _messages[conversationId];
    if (list != null) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].senderId != meId &&
            list[i].status != MessageDeliveryStatus.read) {
          list[i] = list[i].copyWith(status: MessageDeliveryStatus.read);
        }
      }
      _emitMessages(conversationId);
    }
    _emitConversations();
    _emitUnread();
  }

  @override
  Future<Conversation> ensureIndividual({
    required String otherUserId,
    required String otherName,
    required String otherRole,
    String? otherAvatarUrl,
  }) async {
    final existing = _conversations.values.firstWhere(
      (c) =>
          c.kind == ConversationKind.individual &&
          c.participants.any((p) => p.userId == otherUserId),
      orElse: () => Conversation(
        id: 'new-${_uuid.v4().substring(0, 6)}',
        kind: ConversationKind.individual,
        title: otherName,
        participants: [
          ChatParticipant(userId: meId, name: myName, role: myRoleCode, isMe: true),
          ChatParticipant(
            userId: otherUserId,
            name: otherName,
            role: otherRole,
            avatarUrl: otherAvatarUrl,
          ),
        ],
        updatedAt: DateTime.now(),
      ),
    );
    _conversations[existing.id] = existing;
    _messages.putIfAbsent(existing.id, () => []);
    _emitConversations();
    return existing;
  }

  @override
  Future<List<ChatParticipant>> discoverableContacts({String? query}) async {
    final pool = <ChatParticipant>[
      ChatParticipant(userId: 'u-elena', name: 'Prof. Elena Ramírez', role: 'teacher'),
      ChatParticipant(userId: 'u-carlos', name: 'Prof. Carlos Mendoza', role: 'teacher'),
      ChatParticipant(userId: 'u-sara', name: 'Prof. Sara Núñez', role: 'teacher'),
      ChatParticipant(userId: 'u-coord', name: 'Coordinación Académica', role: 'coordinator'),
      ChatParticipant(userId: 'u-director', name: 'Dir. Roberto Castillo', role: 'director'),
      ChatParticipant(userId: 'u-marta', name: 'Marta Hernández (madre)', role: 'parent'),
      ChatParticipant(userId: 'u-javier', name: 'Javier Rojas (padre)', role: 'parent'),
    ];
    final q = query?.toLowerCase().trim() ?? '';
    if (q.isEmpty) return pool;
    return pool
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.role.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<void> setTyping(String conversationId, {required bool typing}) async {
    // En modo demo no propagamos nuestro typing.
  }

  void dispose() {
    _autoResponder?.cancel();
    _conversationsController.close();
    _unreadController.close();
    for (final c in _messagesControllers.values) {
      c.close();
    }
  }
}
