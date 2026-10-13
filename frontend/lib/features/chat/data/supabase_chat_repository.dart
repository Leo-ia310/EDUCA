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
  final _messageCache = <String, List<Message>>{};
  final _messageParticipants = <String, List<ChatParticipant>>{};
  final _messagePollTimers = <String, Timer>{};
  List<Conversation> _conversationCache = const [];
  Timer? _conversationPollTimer;

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

  void _ensureConversationsPolling() {
    _conversationPollTimer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_emitConversationSnapshotSafely()),
    );
  }

  Future<void> _emitConversationSnapshotSafely() async {
    try {
      await _emitConversationSnapshot();
    } catch (_) {
      // El siguiente polling/realtime volverá a intentar.
    }
  }

  @override
  Stream<List<Conversation>> watchConversations() async* {
    final convos = await _fetchConversations();
    yield convos;
    _unreadCtrl.add(convos.fold<int>(0, (s, c) => s + c.unreadCount));
    _ensureConversationsChannel();
    _ensureConversationsPolling();
    yield* _conversationsCtrl.stream;
  }

  @override
  Stream<int> watchTotalUnread() async* {
    final convos = await _fetchConversations();
    yield convos.fold<int>(0, (s, c) => s + c.unreadCount);
    _ensureConversationsChannel();
    _ensureConversationsPolling();
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
    _conversationCache = List.unmodifiable(result);
    return _conversationCache;
  }

  Future<void> _emitConversationSnapshot() async {
    final convos = await _fetchConversations();
    _conversationsCtrl.add(convos);
    _unreadCtrl.add(convos.fold<int>(0, (s, c) => s + c.unreadCount));
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
        .select(
          'user_id, users(id, full_name, avatar_url, user_roles(roles(code)))',
        )
        .eq('conversation_id', conversationId);
    return (rows as List).map((p) {
      final u = p['users'] as Map<String, dynamic>?;
      final userId = p['user_id'].toString();
      return ChatParticipant(
        userId: userId,
        name: u?['full_name'] as String? ?? '—',
        role: _roleCodeFromUser(u),
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
    _messageParticipants[conversationId] = participants;

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
        callback: (_) {
          unawaited(_refreshMessagesSafely(conversationId));
          unawaited(_emitConversationSnapshotSafely());
        },
      );
      ch.subscribe();
      return ch;
    });

    _ensureMessagesPolling(conversationId);

    try {
      final initial = await _fetchMessages(conversationId, participants);
      _setServerMessages(conversationId, initial);
      yield _messageCache[conversationId] ?? const [];
      yield* ctrl.stream;
    } finally {
      _messagePollTimers.remove(conversationId)?.cancel();
    }
  }

  void _ensureMessagesPolling(String conversationId) {
    _messagePollTimers.putIfAbsent(
      conversationId,
      () => Timer.periodic(
        const Duration(seconds: 8),
        (_) => unawaited(_refreshMessagesSafely(conversationId)),
      ),
    );
  }

  Future<void> _refreshMessagesSafely(String conversationId) async {
    try {
      await _refreshMessages(conversationId);
    } catch (_) {
      // El stream mantiene el último estado válido y reintenta luego.
    }
  }

  Future<void> _refreshMessages(String conversationId) async {
    final participants = _messageParticipants[conversationId] ??
        await _participantsFor(conversationId);
    _messageParticipants[conversationId] = participants;
    final messages = await _fetchMessages(conversationId, participants);
    _setServerMessages(conversationId, messages);
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
    final messages = (rows as List)
        .cast<Map<String, dynamic>>()
        .map<Message>((r) => _msgFromRow(r, participants: participants))
        .toList();
    messages.sort(_compareMessages);
    return messages;
  }

  void _setServerMessages(String conversationId, List<Message> serverMessages) {
    final existing = _messageCache[conversationId] ?? const <Message>[];
    final localTransient = existing.where(
      (message) =>
          message.id.startsWith('local-') &&
          (message.status == MessageDeliveryStatus.sending ||
              message.status == MessageDeliveryStatus.failed) &&
          !serverMessages
              .any((remote) => _looksLikeSameMessage(message, remote)),
    );
    _setMessages(conversationId, [...serverMessages, ...localTransient]);
  }

  void _upsertMessage(String conversationId, Message message) {
    final current = _messageCache[conversationId] ?? const <Message>[];
    _setMessages(conversationId, [
      ...current.where((m) => m.id != message.id && m.uuid != message.uuid),
      message,
    ]);
  }

  void _replaceMessage(
    String conversationId,
    Message previous,
    Message replacement,
  ) {
    final current = _messageCache[conversationId] ?? const <Message>[];
    _setMessages(conversationId, [
      ...current.where(
        (m) =>
            m.id != previous.id &&
            m.uuid != previous.uuid &&
            m.id != replacement.id &&
            m.uuid != replacement.uuid,
      ),
      replacement,
    ]);
  }

  void _setMessages(String conversationId, List<Message> messages) {
    final byKey = <String, Message>{};
    for (final message in messages) {
      byKey[message.id.startsWith('local-') ? message.uuid : message.id] =
          message;
    }
    final sorted = byKey.values.toList()..sort(_compareMessages);
    _messageCache[conversationId] = List.unmodifiable(sorted);
    final ctrl = _messagesCtrls[conversationId];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(_messageCache[conversationId]!);
    }
  }

  int _compareMessages(Message a, Message b) {
    final byDate = a.sentAt.compareTo(b.sentAt);
    if (byDate != 0) return byDate;
    return a.id.compareTo(b.id);
  }

  bool _looksLikeSameMessage(Message local, Message remote) {
    final sameAttachment = local.attachment?.id == remote.attachment?.id;
    final sameText = (local.content ?? '') == (remote.content ?? '');
    final closeEnough = remote.sentAt.difference(local.sentAt).abs() <
        const Duration(minutes: 2);
    return local.senderId == remote.senderId &&
        sameText &&
        sameAttachment &&
        closeEnough;
  }

  void _applyConversationMessage(Message message) {
    if (_conversationCache.isEmpty) return;
    final updated = _conversationCache
        .map(
          (conversation) => conversation.id == message.conversationId
              ? conversation.copyWith(
                  lastMessage: message,
                  updatedAt: message.sentAt,
                )
              : conversation,
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _conversationCache = List.unmodifiable(updated);
    _conversationsCtrl.add(_conversationCache);
    _unreadCtrl.add(
      _conversationCache.fold<int>(
        0,
        (sum, conversation) => sum + conversation.unreadCount,
      ),
    );
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
      sentAt: _parseDate(r['created_at'] as String?),
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
    final local = _localMessage(
      conversationId: conversationId,
      content: content,
      attachment: attachment,
      replyTo: replyTo,
    );
    _upsertMessage(conversationId, local);
    _applyConversationMessage(local);

    try {
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
      final message =
          _msgFromApi(Map<String, dynamic>.from(data['message'] as Map));
      _replaceMessage(conversationId, local, message);
      _applyConversationMessage(message);
      await _emitConversationSnapshot();
      return message;
    } catch (_) {
      final failed = local.copyWith(status: MessageDeliveryStatus.failed);
      _replaceMessage(conversationId, local, failed);
      _applyConversationMessage(failed);
      rethrow;
    }
  }

  @override
  Future<void> markAsRead(String conversationId) async {
    await _api.call('chat.markAsRead', {'conversationId': conversationId});
    await _emitConversationSnapshot();
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
    await _emitConversationSnapshot();
    return conv ?? (throw StateError('No se pudo crear la conversación'));
  }

  @override
  Future<List<ChatParticipant>> discoverableContacts({String? query}) async {
    final rows = await _client
        .from('users')
        .select('id, full_name, email, avatar_url, user_roles(roles(code))')
        .eq('institution_id', institutionId)
        .eq('active', true)
        .filter('deleted_at', 'is', null)
        .neq('id', meUserId)
        .limit(60);
    final needle = query?.trim().toLowerCase() ?? '';
    return (rows as List)
        .map<ChatParticipant>((r) {
          final row = r as Map<String, dynamic>;
          final role = _roleCodeFromUser(row);
          return ChatParticipant(
            userId: row['id'].toString(),
            name: row['full_name'] as String? ?? '—',
            role: role,
            avatarUrl: row['avatar_url'] as String?,
          );
        })
        .where((contact) {
          if (needle.isEmpty) return true;
          return contact.name.toLowerCase().contains(needle) ||
              contact.role.toLowerCase().contains(needle) ||
              _roleLabel(contact.role).toLowerCase().contains(needle);
        })
        .take(30)
        .toList();
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
    _conversationPollTimer?.cancel();
    for (final timer in _messagePollTimers.values) {
      timer.cancel();
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
      sentAt: _parseDate(r['sentAt'] as String?),
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

  Message _localMessage({
    required String conversationId,
    String? content,
    MessageAttachment? attachment,
    Message? replyTo,
  }) {
    final now = DateTime.now();
    final localId = 'local-${now.microsecondsSinceEpoch}';
    return Message(
      id: localId,
      uuid: localId,
      conversationId: conversationId,
      senderId: meUserId,
      senderName: myName,
      sentAt: now,
      content: content,
      attachment: attachment,
      replyTo: replyTo,
      status: MessageDeliveryStatus.sending,
    );
  }

  DateTime _parseDate(String? raw) =>
      DateTime.tryParse(raw ?? '')?.toLocal() ?? DateTime.now();

  String _roleCodeFromUser(Map<String, dynamic>? user) {
    final roles = user?['user_roles'];
    if (roles is! List || roles.isEmpty) return '';
    final codes = roles
        .map((entry) {
          if (entry is! Map) return null;
          final role = entry['roles'];
          if (role is! Map) return null;
          return role['code'] as String?;
        })
        .whereType<String>()
        .toSet();
    const priority = [
      'admin',
      'director',
      'coordinator',
      'teacher',
      'parent',
      'student',
      'support',
    ];
    for (final code in priority) {
      if (codes.contains(code)) return code;
    }
    return codes.isEmpty ? '' : codes.first;
  }

  String _roleLabel(String code) => switch (code) {
        'teacher' => 'Maestro',
        'parent' => 'Padre',
        'student' => 'Estudiante',
        'admin' => 'Administrador',
        'coordinator' => 'Coordinador',
        'director' => 'Director',
        'support' => 'Soporte',
        _ => code,
      };
}
