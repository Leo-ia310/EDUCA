import 'dart:async';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/chat/data/supabase_chat_repository.dart';
import 'package:educa360/features/chat/presentation/widgets/chat_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Api extends BackendApiClient {
  _Api(SupabaseClient superClient) : super(supabase: superClient);
  final keys = <String>[];
  bool loseResponse = true;
  Completer<void>? gate;
  @override
  Future<dynamic> call(String action,
      [Map<String, dynamic> payload = const {},]) async {
    final key = payload['requestId'] as String;
    keys.add(key);
    if (gate != null) await gate!.future;
    if (loseResponse) {
      loseResponse = false;
      throw BackendApiException('Respuesta perdida', retryable: true);
    }
    return {
      'message': {
        'id': '22',
        'uuid': key,
        'conversationId': payload['conversationId'],
        'senderId': '1',
        'senderName': 'Me',
        'sentAt': '2026-10-19T12:00:00Z',
        'content': payload['content'],
        'attachment': null,
      },
    };
  }

  @override
  Future<dynamic> get(String path,
          {Map<String, dynamic>? queryParameters,
          bool authenticated = true,}) async =>
      {'conversations': [], 'totalUnread': 0, 'nextCursor': null};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late _Api api;
  final repositories = <SupabaseChatRepository>[];
  SupabaseChatRepository repository({String me = '1'}) {
    final r = SupabaseChatRepository(
        client: client,
        api: api,
        meUserId: me,
        myName: 'Me',
        institutionId: 10,
        enableRealtime: false,);
    repositories.add(r);
    return r;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    client = SupabaseClient('https://fixture.supabase.co', 'fixture-public');
    api = _Api(client);
  });
  tearDown(() async {
    for (final r in repositories) {
      r.dispose();
    }
    repositories.clear();
    await client.dispose();
  });
  test(
      'lost response preserves only fingerprint/UUID across repository recreation; a new identical message gets another UUID',
      () async {
    final first = repository();
    await expectLater(
        first.sendMessage(conversationId: '7', content: 'Private text'),
        throwsA(isA<BackendApiException>()),);
    first.dispose();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), hasLength(1));
    expect(preferences.getKeys().single, startsWith('chat_send_v1.'));
    expect(preferences.getKeys().map(preferences.get).join(),
        isNot(contains('Private text')),);
    final second = repository();
    await second.sendMessage(conversationId: '7', content: 'Private text');
    expect(api.keys[1], api.keys[0]);
    await second.sendMessage(conversationId: '7', content: 'Private text');
    expect(api.keys[2], isNot(api.keys[0]));
    expect(preferences.getKeys(), isEmpty);
  });
  test(
      'double invocation shares one request and disposed repositories cannot send',
      () async {
    api.loseResponse = false;
    api.gate = Completer<void>();
    final r = repository();
    final a = r.sendMessage(conversationId: '7', content: 'Same'),
        b = r.sendMessage(conversationId: '7', content: 'Same');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(api.keys, hasLength(1));
    api.gate!.complete();
    expect((await a).uuid, (await b).uuid);
    r.dispose();
    await expectLater(
        r.sendMessage(conversationId: '7', content: 'New'), throwsStateError,);
    expect(api.keys, hasLength(1));
  });
  testWidgets(
      'input retains failed text, prevents double submit and clears only on confirmation',
      (tester) async {
    final gate = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
            body: ChatInput(
                onSend: (text) {
                  calls++;
                  return gate.future;
                },
                onPickAttachment: () async {},),),),);
    await tester.enterText(find.byType(TextField), 'Keep this draft');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Keep this draft'), findsOneWidget);
    gate.complete(false);
    await tester.pump();
    expect(find.text('Keep this draft'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
            body: ChatInput(
                onSend: (text) async => true, onPickAttachment: () async {},),),),);
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(find.text('Keep this draft'), findsNothing);
  });
}
