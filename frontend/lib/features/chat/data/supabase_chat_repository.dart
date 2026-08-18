import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/chat_repository.dart';
import '../domain/entities.dart';

const _uuid = Uuid();

/// Implementación real contra Supabase.
///
/// Tablas usadas (ver `supabase/migrations/0002_init_academic_extras.sql`):
/// - `conversations`
/// - `conversation_participants`
/// - `messages`
/// - `message_reads`
///
/// La suscripción realtime se hace vía `client.channel(...)` filtrando por
/// `conversation_id`. Los deltas se aplican al StreamController local para
/// que el widget no tenga que recargar todo.
///
/// Esta implementación cubre el flujo mínimo funcional; los TODOs marcan
/// campos avanzados (reply_to, editado, adjuntos vía `files`) que se
/// completan cuando el resto del backend esté cableado.
class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository({
    required SupabaseClient client,
    required this.meUserId,
    required this.myName,
    required this.institutionId,
  }) : _client = client;

  final SupabaseClient _client;
  final String meUserId;
  final String myName;
  final int institutionId;

  final _conversationsCtrl =
      StreamController<List<Conversation>>.broadcast();
  final _messagesCtrls = <String, StreamController<List<Message>>>{};
  final _unreadCtrl = StreamController<int>.broadcast();

  final _channels = <String, RealtimeChannel>{};

  @override
  Stream<List<Conversation>> watchConversations() async* {
    yield await _fetchConversations();
    yield* _conversationsCtrl.stream;

    // Un solo canal para nuestras conversaciones — al recibir inserts en
    // `messages` de una conversación donde participo, recargo.
    _channels.putIfAbsent('conversations', () {
      final ch = _client.channel('my-conversations');
      ch.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) async {
          _conversationsCtrl.add(await _fetchConversations());
        },
      );
      ch.subscribe();
      return ch;
    });
  }

  Future<List<Conversation>> _fetchConversations() async {
    final rows = await _client
        .from('conversation_participants')
        .select(
          'conversation_id, conversations(id, kind, title, created_at)',
        )
        .eq('user_id', meUserId);

    // TODO: enriquecer con lastMessage + unreadCount vía RPC/joins.
    final result = <Conversation>[];
    for (final r in rows) {
      final conv = r['conversations'] as Map<String, dynamic>?;
      if (conv == null) continue;
      result.add(Conversation(
        id: conv['id'].toString(),
        kind: (conv['kind'] as String?) == 'group'
            ? ConversationKind.group
            : ConversationKind.individual,
        title: conv['title'] as String? ?? '',
        participants: const [],
        updatedAt:
            DateTime.tryParse(conv['created_at'] as String? ?? '') ??
                DateTime.now(),
      ));
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  @override
  Future<Conversation?> conversationById(String id) async {
    final row = await _client
        .from('conversations')
        .select('id, kind, title, created_at')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Conversation(
      id: row['id'].toString(),
      kind: (row['kind'] as String?) == 'group'
          ? ConversationKind.group
          : ConversationKind.individual,
      title: row['title'] as String? ?? '',
      participants: const [],
      updatedAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  Stream<List<Message>> watchMessages(String conversationId) async* {
    final ctrl = _messagesCtrls.putIfAbsent(
      conversationId,
      () => StreamController<List<Message>>.broadcast(),
    );

    // Suscripción al canal específico.
    _channels.putIfAbsent(conversationId, () {
      final ch = _client.channel('messages:$conversationId');
      ch.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: conversationId,
        ),
        callback: (payload) {
          ctrl.add([_msgFromRow(payload.newRecord)]);
        },
      );
      ch.subscribe();
      return ch;
    });

    yield await _fetchMessages(conversationId);
    yield* ctrl.stream;
  }

  Future<List<Message>> _fetchMessages(String conversationId) async {
    final rows = await _client
        .from('messages')
        .select('id, uuid, conversation_id, sender_id, content, created_at')
        .eq('conversation_id', conversationId)
        .order('created_at');
    return rows.map<Message>((r) => _msgFromRow(r)).toList();
  }

  Message _msgFromRow(Map<String, dynamic> r) {
    return Message(
      id: r['id'].toString(),
      uuid: r['uuid'].toString(),
      conversationId: r['conversation_id'].toString(),
      senderId: r['sender_id'].toString(),
      senderName: r['sender_id'].toString() == meUserId ? myName : 'Usuario',
      sentAt:
          DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
      content: r['content'] as String?,
      status: MessageDeliveryStatus.delivered,
    );
  }

  @override
  Future<Message> sendMessage({
    required String conversationId,
    String? content,
    MessageAttachment? attachment,
    Message? replyTo,
  }) async {
    final uuid = _uuid.v4();
    final row = await _client
        .from('messages')
        .insert({
          'uuid': uuid,
          'conversation_id': conversationId,
          'sender_id': meUserId,
          'content': content,
          // TODO: mapear attachment → file_id (subir con SupabaseFileUploadService).
        })
        .select('id, uuid, conversation_id, sender_id, content, created_at')
        .single();
    return _msgFromRow(row);
  }

  @override
  Future<void> markAsRead(String conversationId) async {
    // TODO: insertar en `message_reads` para cada mensaje sin leer.
  }

  @override
  Future<Conversation> ensureIndividual({
    required String otherUserId,
    required String otherName,
    required String otherRole,
    String? otherAvatarUrl,
  }) async {
    // TODO: buscar conversación existente por participantes o crear una nueva
    // via RPC atómica para evitar race conditions.
    throw UnimplementedError('ensureIndividual: TODO en Supabase');
  }

  @override
  Stream<int> watchTotalUnread() => _unreadCtrl.stream;

  @override
  Future<List<ChatParticipant>> discoverableContacts({String? query}) async {
    var q = _client
        .from('users')
        .select('id, full_name, email')
        .eq('institution_id', institutionId);
    if (query != null && query.trim().isNotEmpty) {
      q = q.ilike('full_name', '%${query.trim()}%');
    }
    final rows = await q.limit(30);
    return rows.map<ChatParticipant>((r) {
      return ChatParticipant(
        userId: r['id'].toString(),
        name: r['full_name'] as String? ?? '—',
        role: '',
      );
    }).toList();
  }

  @override
  Future<void> setTyping(String conversationId, {required bool typing}) async {
    // Broadcast por presencia realtime.
    final ch = _channels[conversationId];
    if (ch == null) return;
    // TODO: usar channel.presence para publicar 'typing'.
  }

  void dispose() {
    for (final ch in _channels.values) {
      _client.removeChannel(ch);
    }
    _conversationsCtrl.close();
    _unreadCtrl.close();
    for (final c in _messagesCtrls.values) {
      c.close();
    }
  }
}
