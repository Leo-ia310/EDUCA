import 'dart:async';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/features/chat/data/supabase_chat_repository.dart';
import 'package:educa360/features/chat/domain/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _conversation(String id) => {
      'id': id,
      'kind': 'individual',
      'title': 'Conversation $id',
      'unreadCount': 3,
      'updatedAt': '2026-10-18T10:00:00Z',
      'lastMessage': null,
      'participants': [
        {'userId': '1', 'name': 'Me', 'role': 'parent', 'isMe': true},
      ],
    };
Map<String, dynamic> _message(int id) => {
      'id': '$id',
      'uuid': 'message-$id',
      'conversationId': '1',
      'senderId': '2',
      'senderName': 'Other',
      'sentAt': '2026-10-18T10:00:00Z',
      'content': 'Message $id',
      'attachment': null,
      'read': id < 200,
    };

class _ChatApi extends BackendApiClient {
  _ChatApi(SupabaseClient client) : super(supabase: client);
  final requests = <({String path, Map<String, dynamic> query})>[];
  Completer<dynamic>? pending;
  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final query = queryParameters ?? {};
    requests.add((path: path, query: query));
    if (pending != null) return pending!.future;
    if (path == '/chats/conversations') {
      return {
        'conversations': [
          _conversation(
            query.containsKey('afterId')
                ? '2'
                : query.containsKey('q')
                    ? '3'
                    : '1',
          ),
        ],
        'totalUnread': 500,
        'nextCursor': query.containsKey('afterId') || query.containsKey('q')
            ? null
            : {'updatedAt': '2026-10-18T10:00:00.123456Z', 'id': '1'},
      };
    }
    final before = query['beforeId'], after = query['afterId'];
    final rows = before != null
        ? List.generate(100, (i) => _message(i + 1))
        : after != null
            ? (after == '200' ? [_message(201)] : <Map<String, dynamic>>[])
            : List.generate(100, (i) => _message(i + 101));
    return {
      'messages': rows,
      'hasMore': before == null && after == null,
      'nextBeforeId': rows.isEmpty ? null : rows.first['id'],
      'nextAfterId': rows.isEmpty ? null : rows.last['id'],
    };
  }
}

Future<void> _tick([Duration delay = Duration.zero]) =>
    Future<void>.delayed(delay);
Future<void> _cancel(StreamSubscription<dynamic> subscription) async {
  await subscription.cancel();
  await _tick();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late _ChatApi api;
  late SupabaseChatRepository repository;
  setUp(() {
    client = SupabaseClient('https://fixture.supabase.co', 'fixture-public');
    api = _ChatApi(client);
    repository = SupabaseChatRepository(
      client: client,
      api: api,
      meUserId: '1',
      myName: 'Me',
      institutionId: 10,
      enableRealtime: false,
      messagePollEvery: const Duration(milliseconds: 200),
    );
  });
  tearDown(() async {
    repository.dispose();
    await client.dispose();
  });

  test(
      'list and badge share one request; load-more preserves cursor precision and global unread',
      () async {
    var conversations = <Conversation>[];
    var unread = 0;
    final list = repository
        .watchConversations()
        .listen((value) => conversations = value);
    final badge =
        repository.watchTotalUnread().listen((value) => unread = value);
    await _tick();
    expect(api.requests.length, 1);
    expect(conversations.length, 1);
    expect(unread, 500);
    expect(repository.hasMoreConversations, isTrue);
    await repository.loadMoreConversations();
    await _tick();
    expect(api.requests.length, 2);
    expect(conversations.map((c) => c.id), ['1', '2']);
    expect(
      api.requests.last.query['afterUpdatedAt'],
      '2026-10-18T10:00:00.123456Z',
    );
    expect(repository.hasMoreConversations, isFalse);
    expect(unread, 500);
    await repository.searchConversations('Teacher');
    await _tick();
    expect(api.requests.last.query['q'], 'Teacher');
    expect(conversations.single.id, '3');
    repository.dispose();
    final count = api.requests.length;
    await _tick(const Duration(milliseconds: 50));
    expect(api.requests.length, count);
    await _cancel(list);
    await _cancel(badge);
    await _tick();
  });

  test(
      'history appends older pages and polling reads only deltas; cancellation stops polling',
      () async {
    var messages = <Message>[];
    final subscription =
        repository.watchMessages('1').listen((value) => messages = value);
    await _tick();
    expect(messages.length, 100);
    expect(repository.hasOlderMessages('1'), isTrue);
    expect(messages.first.id, '101');
    expect(messages.last.id, '200');
    await repository.loadOlderMessages('1');
    await _tick();
    expect(messages.length, 200);
    expect(messages.first.id, '1');
    expect(messages[9].id, '10');
    expect(api.requests.last.query['beforeId'], '101');
    expect(repository.hasOlderMessages('1'), isFalse);
    await _tick(const Duration(milliseconds: 300));
    expect(api.requests.any((request) => request.query['afterId'] == '200'),
        isTrue,);
    expect(messages.length, 201);
    expect(messages.first.status, MessageDeliveryStatus.read);
    expect(messages.last.id, '201');
    await _cancel(subscription);
    await _tick();
    final count = api.requests.length;
    await _tick(const Duration(milliseconds: 250));
    expect(api.requests.length, count);
  });

  test(
      'late response after disposal closes without emitting data or scheduling work',
      () async {
    api.pending = Completer<dynamic>();
    var events = 0;
    final subscription =
        repository.watchConversations().listen((_) => events++);
    await _tick();
    repository.dispose();
    api.pending!.complete({
      'conversations': [_conversation('1')],
      'totalUnread': 3,
      'nextCursor': null,
    });
    await _tick();
    await _tick(const Duration(milliseconds: 250));
    expect(events, 0);
    expect(api.requests.length, 1);
    await _cancel(subscription);
    await _tick();
  });
  test(
      'background suspends message polling and resume reconciles a fresh bounded window',
      () async {
    var messages = <Message>[];
    final subscription =
        repository.watchMessages('1').listen((value) => messages = value);
    await _tick();
    await repository.loadOlderMessages('1');
    await _tick();
    expect(messages.length, 200);
    repository.didChangeAppLifecycleState(AppLifecycleState.paused);
    final count = api.requests.length;
    await _tick(const Duration(milliseconds: 300));
    expect(api.requests.length, count);
    repository.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _tick();
    expect(api.requests.last.query['afterId'], isNull);
    expect(messages.length, 100);
    await _cancel(subscription);
  });
}
