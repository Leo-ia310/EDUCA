import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/backend_api_client.dart';
import '../domain/chat_repository.dart';
import '../domain/entities.dart';

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
class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository({
    required SupabaseClient client,
    required BackendApiClient api,
    required this.meUserId,
    required this.myName,
    required this.institutionId,
  })  : _client = client,
        _api = api;

  final SupabaseClient _client;
  final BackendApiClient _api;
  final String meUserId;
  final String myName;
  final int institutionId;

  static const _messageSelect =
      'id, uuid, conversation_id, sender_id, content, created_at, '
      'files(id, original_name, url, size_bytes, mime_type)';

  final _conversationsCtrl = StreamController<List<Conversation>>.broadcast();
  final _messagesCtrls = <String, StreamController<List<Message>>>{};
  final _unreadCtrl = StreamController<int>.broadcast();

  final _channels = <String, RealtimeChannel>{};

  void _ensureConversationsChannel() {
    _channels.putIfAbsent('conversations', () {
      final ch = _client.channel('my-conversations');
      ch.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) async {
          final convos = await _fetchConversations();
          _conversationsCtrl.add(convos);
          _unreadCtrl.add(convos.fold<int>(0, (s, c) => s + c.unreadCount));
        },
      );
      ch.subscribe();
      return ch;
    });
  }

  @override
  Stream<List<Conversation>> watchConversations() async* {
    final convos = await _fetchConversations();
    yield convos;
    _unreadCtrl.add(convos.fold<int>(0, (s, c) => s + c.unreadCount));
    _ensureConversationsChannel();
    yield* _conversationsCtrl.stream;
  }

  @override
  Stream<int> watchTotalUnread() async* {
    final convos = await _fetchConversations();
    yield convos.fold<int>(0, (s, c) => s + c.unreadCount);
    _ensureConversationsChannel();
    yield* _unreadCtrl.stream;
  }

  Future<List<Conversation>> _fetchConversations() async {
    final rows = await _client
        .from('conversation_participants')
        .select(
          'conversation_id, conversations(id, kind, title, created_at)',
        )
        .eq('user_id', meUserId);

    final baseById = <String, Map<String, dynamic>>{};
    for (final r in (rows as List)) {
      final conv = r['conversations'] as Map<String, dynamic>?;
      if (conv == null) continue;
      baseById[conv['id'].toString()] = conv;
    }
    if (baseById.isEmpty) return const [];

    final result = await Future.wait(
      baseById.entries.map((e) => _hydrateConversation(e.key, e.value)),
    );
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Future<Conversation> _hydrateConversation(
    String id,
    Map<String, dynamic> conv,
  ) async {
    final participants = await _participantsFor(id);

    final lastRow = await _client
        .from('messages')
        .select(_messageSelect)
        .eq('conversation_id', id)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final lastMessage = lastRow == null
        ? null
        : _msgFromRow(lastRow, participants: participants);

    final unread = await _unreadCountFor(id);
    final title = (conv['title'] as String?)?.isNotEmpty == true
        ? conv['title'] as String
        : participants.where((p) => !p.isMe).map((p) => p.name).join(', ');

    return Conversation(
      id: id,
      kind: (conv['kind'] as String?) == 'group'
          ? ConversationKind.group
          : ConversationKind.individual,
      title: title,
      participants: participants,
      lastMessage: lastMessage,
      unreadCount: unread,
      updatedAt: lastMessage?.sentAt ??
          DateTime.tryParse(conv['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Future<List<ChatParticipant>> _participantsFor(String conversationId) async {
    final rows = await _client
        .from('conversation_participants')
        .select('user_id, role, users(id, full_name, avatar_url)')
        .eq('conversation_id', conversationId);
    return (rows as List).map((p) {
      final u = p['users'] as Map<String, dynamic>?;
      final userId = p['user_id'].toString();
      return ChatParticipant(
        userId: userId,
        name: u?['full_name'] as String? ?? '—',
        role: p['role'] as String? ?? '',
        avatarUrl: u?['avatar_url'] as String?,
        isMe: userId == meUserId,
      );
    }).toList();
  }

  Future<int> _unreadCountFor(String conversationId) async {
    final messages = await _client
        .from('messages')
        .select('id')
        .eq('conversation_id', conversationId)
        .neq('sender_id', meUserId);
    final ids = (messages as List).map((m) => m['id']).toList();
    if (ids.isEmpty) return 0;
    final reads = await _client
        .from('message_reads')
        .select('message_id')
        .eq('user_id', meUserId)
        .inFilter('message_id', ids);
    final readIds =
        (reads as List).map((r) => r['message_id'].toString()).toSet();
    return ids.where((id) => !readIds.contains(id.toString())).length;
  }

  @override
  Future<Conversation?> conversationById(String id) async {
    final row = await _client
        .from('conversations')
        .select('id, kind, title, created_at')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return _hydrateConversation(id, row);
  }

  @override
  Stream<List<Message>> watchMessages(String conversationId) async* {
    final ctrl = _messagesCtrls.putIfAbsent(
      conversationId,
      () => StreamController<List<Message>>.broadcast(),
    );
    final participants = await _participantsFor(conversationId);

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
          ctrl.add(
              [_msgFromRow(payload.newRecord, participants: participants)]);
        },
      );
      ch.subscribe();
      return ch;
    });

    yield await _fetchMessages(conversationId, participants);
    yield* ctrl.stream;
  }

  Future<List<Message>> _fetchMessages(
    String conversationId,
    List<ChatParticipant> participants,
  ) async {
    final rows = await _client
        .from('messages')
        .select(_messageSelect)
        .eq('conversation_id', conversationId)
        .order('created_at');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map<Message>((r) => _msgFromRow(r, participants: participants))
        .toList();
  }

  Message _msgFromRow(
    Map<String, dynamic> r, {
    List<ChatParticipant>? participants,
  }) {
    final senderId = r['sender_id'].toString();
    final sender = participants?.where((p) => p.userId == senderId).firstOrNull;
    final file = r['files'] as Map<String, dynamic>?;
    return Message(
      id: r['id'].toString(),
      uuid: r['uuid'].toString(),
      conversationId: r['conversation_id'].toString(),
      senderId: senderId,
      senderName: senderId == meUserId ? myName : (sender?.name ?? 'Usuario'),
      senderAvatarUrl: sender?.avatarUrl,
      sentAt:
          DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
      content: r['content'] as String?,
      attachment: file == null
          ? null
          : MessageAttachment(
              id: file['id'].toString(),
              name: file['original_name'] as String? ?? 'archivo',
              url: file['url'] as String? ?? '',
              sizeBytes: (file['size_bytes'] as num?)?.toInt(),
              mimeType: file['mime_type'] as String?,
            ),
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
    final response = await _api.call('chat.sendMessage', {
      'conversationId': conversationId,
      'content': content,
      'attachment': attachment == null
          ? null
          : {
              'id': attachment.id,
              'name': attachment.name,
              'url': attachment.url,
              'sizeBytes': attachment.sizeBytes,
              'mimeType': attachment.mimeType,
            },
    });
    final data = Map<String, dynamic>.from(response as Map);
    return _msgFromApi(Map<String, dynamic>.from(data['message'] as Map));
  }

  @override
  Future<void> markAsRead(String conversationId) async {
    await _api.call('chat.markAsRead', {'conversationId': conversationId});
  }

  @override
  Future<Conversation> ensureIndividual({
    required String otherUserId,
    required String otherName,
    required String otherRole,
    String? otherAvatarUrl,
  }) async {
    final response = await _api.call('chat.ensureIndividual', {
      'otherUserId': otherUserId,
    });
    final data = Map<String, dynamic>.from(response as Map);
    final conversationId = data['conversationId'].toString();
    final conv = await conversationById(conversationId);
    return conv ?? (throw StateError('No se pudo crear la conversación'));
  }

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
    final ch = _channels[conversationId];
    if (ch == null) return;
    await ch.sendBroadcastMessage(
      event: 'typing',
      payload: {'userId': meUserId, 'typing': typing},
    );
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

  Message _msgFromApi(Map<String, dynamic> r) {
    final attachment = r['attachment'] == null
        ? null
        : Map<String, dynamic>.from(r['attachment'] as Map);
    return Message(
      id: r['id'].toString(),
      uuid: r['uuid'].toString(),
      conversationId: r['conversationId'].toString(),
      senderId: r['senderId'].toString(),
      senderName: r['senderName'] as String? ?? myName,
      sentAt: DateTime.tryParse(r['sentAt'] as String? ?? '') ?? DateTime.now(),
      content: r['content'] as String?,
      attachment: attachment == null
          ? null
          : MessageAttachment(
              id: attachment['id'].toString(),
              name: attachment['name'] as String? ?? 'archivo',
              url: attachment['url'] as String? ?? '',
              sizeBytes: (attachment['sizeBytes'] as num?)?.toInt(),
              mimeType: attachment['mimeType'] as String?,
            ),
      status: MessageDeliveryStatus.delivered,
    );
  }
}
