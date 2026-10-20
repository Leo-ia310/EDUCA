import 'dart:async';
import 'package:flutter/widgets.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/adaptive_refresh.dart';
import '../domain/chat_repository.dart';
import 'chat_send_receipts.dart';
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
class SupabaseChatRepository
    with WidgetsBindingObserver
    implements ChatRepository {
  SupabaseChatRepository({
    required SupabaseClient client,
    required BackendApiClient api,
    required this.meUserId,
    required this.myName,
    required this.institutionId,
    this.enableRealtime = true,
    this.messagePollEvery = const Duration(seconds: 15),
  })  : _client = client,
        _api = api {
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  final SupabaseClient _client;
  final BackendApiClient _api;
  final String meUserId;
  final String myName;
  final int institutionId;
  final bool enableRealtime;
  final Duration messagePollEvery;

  final _conversationsCtrl = StreamController<List<Conversation>>.broadcast();
  final _messagesCtrls = <String, StreamController<List<Message>>>{};
  final _unreadCtrl = StreamController<int>.broadcast();
  final _channels = <String, RealtimeChannel>{};
  final _messageCache = <String, List<Message>>{};
  final _messageDrivers = <String, AdaptiveRefresh>{};
  final _messageRefreshes = <String, Future<void>>{};
  final _olderCursors = <String, String?>{};
  final _newerCursors = <String, String?>{};
  final _olderAvailable = <String, bool>{};
  final _messageListeners = <String, int>{};
  final _messageGenerations = <String, int>{};
  final _loadingOlder = <String>{};
  List<Conversation> _conversationCache = const [];
  Future<List<Conversation>>? _conversationRefresh;
  AdaptiveRefresh? _conversationDriver;
  bool _foreground = true;
  Map<String, dynamic>? _conversationCursor;
  int _conversationPages = 1, _conversationRevision = 0, _totalUnread = 0;
  String _query = '';
  bool _loadingConversations = false, _disposed = false;

  void _publishConversations() {
    if (_disposed || !_foreground) return;
    _conversationsCtrl.add(_conversationCache);
    _unreadCtrl.add(_totalUnread);
  }

  void _scheduleConversationSnapshot() {
    _conversationDriver?.notifyEvent();
  }

  void _ensureConversationsChannel() {
    if (_disposed) return;
    _conversationDriver ??= AdaptiveRefresh(
      read: _emitConversationSnapshot,
      foreground: _foreground,
    )..start();
    if (enableRealtime) {
      _channels.putIfAbsent('conversations', () {
        final ch = _client.channel('my-conversations:$meUserId');
        for (final table in [
          'messages',
          'message_reads',
          'conversation_participants',
        ]) {
          ch.onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            callback: (_) => _scheduleConversationSnapshot(),
          );
        }
        ch.subscribe(
          (status, error) => _conversationDriver?.setRealtimeHealthy(
              status == RealtimeSubscribeStatus.subscribed,),
        );
        return ch;
      });
    }
  }

  Future<void> _emitConversationSnapshotSafely() async {
    try {
      await _emitConversationSnapshot();
    } catch (_) {/* Retry on the next event/poll. */}
  }

  @override
  Stream<List<Conversation>> watchConversations() async* {
    _ensureConversationsChannel();
    final list = await _fetchConversations();
    if (_disposed) return;
    yield list;
    yield* _conversationsCtrl.stream;
  }

  @override
  Stream<int> watchTotalUnread() async* {
    _ensureConversationsChannel();
    await _fetchConversations();
    if (_disposed) return;
    yield _totalUnread;
    yield* _unreadCtrl.stream;
  }

  Future<List<Conversation>> _fetchConversations() {
    if (!_foreground || _disposed) return Future.value(_conversationCache);
    return _conversationRefresh ??= _readConversationPages().whenComplete(() {
      _conversationRefresh = null;
    });
  }

  Future<List<Conversation>> _readConversationPages() async {
    while (!_disposed && _foreground) {
      final revision = _conversationRevision;
      final result = <String, Conversation>{};
      Map<String, dynamic>? cursor;
      var total = 0;
      for (var page = 0; page < _conversationPages; page++) {
        final data = Map<String, dynamic>.from(
          await _api.get(
            '/chats/conversations',
            queryParameters: {
              'limit': 50,
              if (_query.isNotEmpty) 'q': _query,
              if (cursor != null) 'afterUpdatedAt': cursor['updatedAt'],
              if (cursor != null) 'afterId': cursor['id'],
            },
          ) as Map,
        );
        if (_disposed || revision != _conversationRevision) break;
        total = (data['totalUnread'] as num).toInt();
        for (final row
            in (data['conversations'] as List).cast<Map<String, dynamic>>()) {
          final conversation = _conversationFromApi(row);
          result[conversation.id] = conversation;
        }
        cursor = data['nextCursor'] == null
            ? null
            : Map<String, dynamic>.from(data['nextCursor'] as Map);
        if (cursor == null) break;
      }
      if (_disposed) break;
      if (revision != _conversationRevision) continue;
      _conversationCursor = cursor;
      _totalUnread = total;
      _conversationCache = List.unmodifiable(result.values);
      return _conversationCache;
    }
    return const [];
  }

  Future<void> _emitConversationSnapshot() async {
    await _fetchConversations();
    _publishConversations();
  }

  @override
  bool get hasMoreConversations => _conversationCursor != null;
  @override
  Future<void> loadMoreConversations() async {
    if (_loadingConversations || _disposed) return;
    _loadingConversations = true;
    try {
      if (_conversationRefresh != null) await _conversationRefresh;
      if (_conversationCursor == null || _disposed) return;
      final revision = _conversationRevision, cursor = _conversationCursor!;
      final data = Map<String, dynamic>.from(
        await _api.get(
          '/chats/conversations',
          queryParameters: {
            'limit': 50,
            if (_query.isNotEmpty) 'q': _query,
            'afterUpdatedAt': cursor['updatedAt'],
            'afterId': cursor['id'],
          },
        ) as Map,
      );
      if (_disposed || revision != _conversationRevision) return;
      final merged = {for (final c in _conversationCache) c.id: c};
      for (final row
          in (data['conversations'] as List).cast<Map<String, dynamic>>()) {
        final c = _conversationFromApi(row);
        merged[c.id] = c;
      }
      _conversationPages++;
      _conversationCache = List.unmodifiable(merged.values);
      _conversationCursor = data['nextCursor'] == null
          ? null
          : Map<String, dynamic>.from(data['nextCursor'] as Map);
      _totalUnread = (data['totalUnread'] as num).toInt();
      _publishConversations();
    } finally {
      _loadingConversations = false;
    }
  }

  @override
  Future<void> searchConversations(String query) async {
    if (_query == query.trim() || _disposed) return;
    _query = query.trim();
    _conversationPages = 1;
    _conversationRevision++;
    await _emitConversationSnapshot();
  }

  Conversation _conversationFromApi(Map<String, dynamic> row) => Conversation(
        id: row['id'].toString(),
        kind: row['kind'] == 'group'
            ? ConversationKind.group
            : ConversationKind.individual,
        title: row['title'] as String? ?? '',
        participants: (row['participants'] as List)
            .cast<Map<String, dynamic>>()
            .map(
              (p) => ChatParticipant(
                userId: p['userId'].toString(),
                name: p['name'] as String? ?? '—',
                role: p['role'] as String? ?? '',
                avatarUrl: p['avatarUrl'] as String?,
                isMe: p['userId'].toString() == meUserId,
              ),
            )
            .toList(),
        lastMessage: row['lastMessage'] == null
            ? null
            : _msgFromApi(Map<String, dynamic>.from(row['lastMessage'] as Map)),
        unreadCount: (row['unreadCount'] as num).toInt(),
        updatedAt: _parseDate(row['updatedAt'] as String?),
      );
  @override
  Future<Conversation?> conversationById(String id) async {
    final data = Map<String, dynamic>.from(
      await _api.get(
        '/chats/conversations',
        queryParameters: {'conversationId': id, 'limit': 1},
      ) as Map,
    );
    final rows = data['conversations'] as List;
    return rows.isEmpty
        ? null
        : _conversationFromApi(Map<String, dynamic>.from(rows.first as Map));
  }

  @override
  Stream<List<Message>> watchMessages(String id) async* {
    final ctrl = _messagesCtrls.putIfAbsent(
      id,
      () => StreamController<List<Message>>.broadcast(),
    );
    _messageListeners.update(id, (n) => n + 1, ifAbsent: () => 1);
    _messageDrivers.putIfAbsent(
      id,
      () => AdaptiveRefresh(
        read: () => _refreshMessages(id),
        fallbackEvery: messagePollEvery,
        foreground: _foreground,
      )..start(),
    );
    if (enableRealtime) {
      _channels.putIfAbsent(id, () {
        final ch = _client.channel('messages:$meUserId:$id');
        ch.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: id,
          ),
          callback: (event) {
            unawaited(_applyMessageEvent(id, event));
            _scheduleConversationSnapshot();
          },
        );
        ch.subscribe(
          (status, error) => _messageDrivers[id]?.setRealtimeHealthy(
              status == RealtimeSubscribeStatus.subscribed,),
        );
        return ch;
      });
    }
    try {
      await _refreshMessages(id);
      if (_disposed) return;
      yield _messageCache[id] ?? const [];
      yield* ctrl.stream;
    } finally {
      final listeners = (_messageListeners[id] ?? 1) - 1;
      _messageListeners[id] = listeners;
      if (listeners == 0) {
        _messageDrivers.remove(id)?.dispose();
        _messageGenerations.update(id, (n) => n + 1, ifAbsent: () => 1);
        _messageRefreshes.remove(id);
        _messageCache.remove(id);
        _olderCursors.remove(id);
        _newerCursors.remove(id);
        _olderAvailable.remove(id);
        unawaited(_messagesCtrls.remove(id)?.close() ?? Future<void>.value());
        final channel = _channels.remove(id);
        if (channel != null) unawaited(_client.removeChannel(channel));
      }
    }
  }

  Future<void> _refreshMessagesSafely(String id) async {
    try {
      await _refreshMessages(id);
    } catch (_) {/* Preserve valid state and retry. */}
  }

  Future<void> _applyMessageEvent(
    String id,
    PostgresChangePayload event,
  ) async {
    if (_disposed || !_foreground) return;
    final record = event.eventType == PostgresChangeEvent.delete
        ? event.oldRecord
        : event.newRecord;
    final messageId = record['id']?.toString();
    if (messageId == null) return;
    if (event.eventType == PostgresChangeEvent.insert) {
      final incoming = BigInt.tryParse(messageId),
          after = BigInt.tryParse(_newerCursors[id] ?? '');
      if (after == null || incoming != null && incoming > after) {
        _messageDrivers[id]?.notifyEvent();
        return;
      }
      if ((_messageCache[id] ?? []).any((m) => m.id == messageId)) return;
    }
    if (event.eventType == PostgresChangeEvent.delete ||
        record['deleted_at'] != null) {
      _setMessages(
        id,
        (_messageCache[id] ?? []).where((m) => m.id != messageId).toList(),
      );
      return;
    }
    try {
      final data = Map<String, dynamic>.from(
        await _api.get(
          '/chats/conversations/$id/messages',
          queryParameters: {'messageId': messageId, 'limit': 1},
        ) as Map,
      );
      if (!_disposed) {
        _setServerMessages(
          id,
          (data['messages'] as List)
              .cast<Map<String, dynamic>>()
              .map(_msgFromApi)
              .toList(),
        );
      }
    } catch (_) {
      await _refreshMessagesSafely(id);
    }
  }

  Future<void> _refreshMessages(String id) {
    if (_disposed || !_foreground) return Future<void>.value();
    final running = _messageRefreshes[id];
    if (running != null) return running;
    late final Future<void> pending;
    pending = _readMessageDeltas(id).whenComplete(() {
      if (identical(_messageRefreshes[id], pending)) {
        _messageRefreshes.remove(id);
      }
    });
    _messageRefreshes[id] = pending;
    return pending;
  }

  Future<Map<String, dynamic>> _messagePage(
    String id, {
    String? before,
    String? after,
  }) async =>
      Map<String, dynamic>.from(
        await _api.get(
          '/chats/conversations/$id/messages',
          queryParameters: {
            'limit': 100,
            if (before != null) 'beforeId': before,
            if (after != null) 'afterId': after,
          },
        ) as Map,
      );
  Future<void> _readMessageDeltas(String id) async {
    final generation = _messageGenerations[id] ?? 0;
    var after = _newerCursors[id];
    while (!_disposed) {
      final data = await _messagePage(id, after: after);
      if (_disposed ||
          !_foreground ||
          generation != (_messageGenerations[id] ?? 0)) {
        return;
      }
      final rows = (data['messages'] as List).cast<Map<String, dynamic>>();
      if (after == null) {
        _olderCursors[id] = data['nextBeforeId'] as String?;
        _olderAvailable[id] = data['hasMore'] as bool;
      }
      _newerCursors[id] = data['nextAfterId'] as String? ?? after;
      _setServerMessages(id, rows.map(_msgFromApi).toList());
      if (after == null || data['hasMore'] != true || rows.isEmpty) break;
      after = data['nextAfterId'] as String?;
    }
  }

  @override
  bool hasOlderMessages(String id) => _olderAvailable[id] ?? false;
  @override
  Future<void> loadOlderMessages(String id) async {
    if (_disposed || !_foreground || !_loadingOlder.add(id)) return;
    final generation = _messageGenerations[id] ?? 0;
    try {
      if (!hasOlderMessages(id)) return;
      final data = await _messagePage(id, before: _olderCursors[id]);
      if (_disposed ||
          !_foreground ||
          generation != (_messageGenerations[id] ?? 0)) {
        return;
      }
      _olderCursors[id] = data['nextBeforeId'] as String?;
      _olderAvailable[id] = data['hasMore'] as bool;
      _setServerMessages(
        id,
        (data['messages'] as List)
            .cast<Map<String, dynamic>>()
            .map(_msgFromApi)
            .toList(),
      );
    } finally {
      _loadingOlder.remove(id);
    }
  }

  void _setServerMessages(String conversationId, List<Message> serverMessages) {
    final existing = _messageCache[conversationId] ?? const <Message>[];
    final remoteIds = serverMessages.map((message) => message.id).toSet();
    final localTransient = existing.where(
      (message) =>
          message.id.startsWith('local-') &&
          (message.status == MessageDeliveryStatus.sending ||
              message.status == MessageDeliveryStatus.failed) &&
          !serverMessages
              .any((remote) => _looksLikeSameMessage(message, remote)),
    );
    _setMessages(conversationId, [
      ...existing.where(
        (message) =>
            !message.id.startsWith('local-') && !remoteIds.contains(message.id),
      ),
      ...serverMessages,
      ...localTransient,
    ]);
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
    if (!_disposed && _foreground && ctrl != null && !ctrl.isClosed) {
      ctrl.add(_messageCache[conversationId]!);
    }
  }

  int _compareMessages(Message a, Message b) {
    final byDate = a.sentAt.compareTo(b.sentAt);
    if (byDate != 0) return byDate;
    final aId = BigInt.tryParse(a.id), bId = BigInt.tryParse(b.id);
    return aId != null && bId != null
        ? aId.compareTo(bId)
        : a.id.compareTo(b.id);
  }

  bool _looksLikeSameMessage(Message local, Message remote) =>
      local.uuid == remote.uuid;

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
    _publishConversations();
  }

  final _pendingSends = <String, Future<Message>>{};

  @override
  Future<Message> sendMessage({
    required String conversationId,
    String? content,
    MessageAttachment? attachment,
    Message? replyTo,
  }) {
    final receipts = ChatSendReceipts('$institutionId:$meUserId');
    final slot = receipts.slot(conversationId, content, attachment?.id);
    final pending = _pendingSends[slot];
    if (pending != null) return pending;
    late final Future<Message> operation;
    operation = _sendMessage(
            receipts, slot, conversationId, content, attachment, replyTo,)
        .whenComplete(() {
      if (identical(_pendingSends[slot], operation)) {
        _pendingSends.remove(slot);
      }
    });
    _pendingSends[slot] = operation;
    return operation;
  }

  Future<Message> _sendMessage(
    ChatSendReceipts receipts,
    String slot,
    String conversationId,
    String? content,
    MessageAttachment? attachment,
    Message? replyTo,
  ) async {
    if (_disposed) throw StateError('La sesión del chat terminó.');
    final requestId = await receipts.begin(slot);
    if (_disposed) throw StateError('La sesión del chat terminó.');
    final local = _localMessage(
      requestId: requestId,
      conversationId: conversationId,
      content: content,
      attachment: attachment,
      replyTo: replyTo,
    );
    _upsertMessage(conversationId, local);
    _applyConversationMessage(local);
    try {
      final response = await _api.call('chat.sendMessage', {
        'requestId': requestId,
        'conversationId': conversationId,
        'content': content,
        'attachment': attachment == null ? null : {'id': attachment.id},
      });
      final data = Map<String, dynamic>.from(response as Map);
      final message =
          _msgFromApi(Map<String, dynamic>.from(data['message'] as Map));
      if (message.uuid != requestId ||
          message.conversationId != conversationId ||
          message.senderId != meUserId) {
        throw StateError('La confirmación no corresponde al mensaje enviado.');
      }
      await receipts.confirm(slot, requestId);
      if (!_disposed) {
        _replaceMessage(conversationId, local, message);
        _applyConversationMessage(message);
        unawaited(_emitConversationSnapshotSafely());
      }
      return message;
    } catch (_) {
      if (!_disposed) {
        final failed = local.copyWith(status: MessageDeliveryStatus.failed);
        _replaceMessage(conversationId, local, failed);
        _applyConversationMessage(failed);
      }
      rethrow;
    }
  }

  @override
  Future<void> markAsRead(String conversationId) async {
    await _api.call('chat.markAsRead', {'conversationId': conversationId});
    _conversationRevision++;
    final unread = _conversationCache
            .where((c) => c.id == conversationId)
            .firstOrNull
            ?.unreadCount ??
        0;
    _totalUnread = (_totalUnread - unread).clamp(0, _totalUnread);
    _conversationCache = List.unmodifiable([
      for (final c in _conversationCache)
        c.id == conversationId ? c.copyWith(unreadCount: 0) : c,
    ]);
    _publishConversations();
    await _emitConversationSnapshotSafely();
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
    final data = Map<String, dynamic>.from(await _api.get('/chats/contacts',
        queryParameters: {'q': query, 'limit': 40},) as Map,);
    return (data['contacts'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (row) => ChatParticipant(
            userId: row['userId'].toString(),
            name: row['name'] as String? ?? 'Usuario',
            role: row['role'] as String? ?? '',
            avatarUrl: row['avatarUrl'] as String?,
          ),
        )
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    _conversationRevision++;
    _newerCursors.clear();
    for (final id in _messageDrivers.keys) {
      _messageGenerations.update(id, (n) => n + 1, ifAbsent: () => 1);
      if (foreground) {
        _messageCache[id] = (_messageCache[id] ?? [])
            .where((m) => m.id.startsWith('local-'))
            .toList();
        _olderCursors.remove(id);
        _olderAvailable.remove(id);
      }
    }
    _conversationDriver?.setForeground(foreground);
    for (final driver in _messageDrivers.values) {
      driver.setForeground(foreground);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    for (final ch in _channels.values) {
      _client.removeChannel(ch);
    }
    _conversationDriver?.dispose();
    for (final driver in _messageDrivers.values) {
      driver.dispose();
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
      status: r['read'] == true
          ? MessageDeliveryStatus.read
          : MessageDeliveryStatus.delivered,
    );
  }

  Message _localMessage({
    required String requestId,
    required String conversationId,
    String? content,
    MessageAttachment? attachment,
    Message? replyTo,
  }) {
    final now = DateTime.now();
    final localId = 'local-$requestId';
    return Message(
      id: localId,
      uuid: requestId,
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
}
