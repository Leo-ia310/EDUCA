import 'dart:async';

import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/core/widgets/educa_bottom_nav.dart';
import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/domain/auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:educa360/features/chat/data/mock_chat_repository.dart';
import 'package:educa360/features/chat/domain/entities.dart';
import 'package:educa360/features/chat/presentation/screens/chat_screen.dart';
import 'package:educa360/features/chat/providers.dart';
import 'package:educa360/features/notifications/domain/notifications_repository.dart';
import 'package:educa360/features/notifications/providers.dart';
import 'package:educa360/shared/models/app_role.dart';
import 'package:educa360/shared/models/app_user.dart';
import 'package:educa360/shared/models/institution.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

class _AdminAuth extends MockAuthRepository {
  @override
  Future<AuthSession?> currentSession() async => const AuthSession(
        institution: Institution(id: 1, code: 'TEST', name: 'Test'),
        user: AppUser(
          id: '42',
          institutionId: 1,
          email: 'admin@demo.com',
          fullName: 'Admin',
          roles: [AppRole.admin],
          activeRole: AppRole.admin,
        ),
      );
}

class _Alerts implements NotificationsRepository {
  int refreshes = 0;
  @override
  Future<void> refresh() async {
    refreshes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Chat extends MockChatRepository {
  _Chat() : super(meId: '42', myName: 'Admin', myRoleCode: 'admin');
  final messages = StreamController<List<Message>>.broadcast();
  final totals = StreamController<int>.broadcast();
  int unread = 1;
  int otherUnread = 0;
  int reads = 0;
  bool fail = false;
  final items = <Message>[];

  void arrive() {
    final id = '${items.length + 1}';
    items.add(
      Message(
        id: id,
        uuid: id,
        conversationId: '1',
        senderId: '99',
        senderName: 'Teacher',
        sentAt: DateTime(2026),
        status: MessageDeliveryStatus.sent,
        content: 'Mensaje $id',
      ),
    );
    unread++;
    totals.add(unread + otherUnread);
    messages.add(List.of(items));
  }

  @override
  Stream<List<Message>> watchMessages(String conversationId) async* {
    yield List.of(items);
    yield* messages.stream;
  }

  @override
  Stream<List<Conversation>> watchConversations() => Stream.value(const []);
  @override
  Stream<int> watchTotalUnread() async* {
    yield unread + otherUnread;
    yield* totals.stream;
  }

  @override
  Future<void> markAsRead(String conversationId) async {
    if (fail) throw StateError('offline');
    reads++;
    unread = 0;
    totals.add(otherUnread);
  }

  @override
  void dispose() {
    messages.close();
    totals.close();
    super.dispose();
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  for (final (others, fails) in [(0, false), (2, false), (0, true)]) {
    testWidgets('admin reads chat; other unread=$others, retry=$fails',
        (tester) async {
      final chat = _Chat()
        ..otherUnread = others
        ..fail = fails;
      final alerts = _Alerts();
      final router = GoRouter(
        initialLocation: '/chat/1',
        routes: [
          GoRoute(
            path: '/chat/1',
            builder: (_, __) => const Scaffold(
              body: ChatScreen(conversationId: '1'),
              bottomNavigationBar: EducaBottomNav(),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_AdminAuth()),
            chatRepositoryProvider.overrideWithValue(chat),
            notificationsRepositoryProvider.overrideWithValue(alerts),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (fails) {
        expect(chat.reads, 0);
        expect(alerts.refreshes, 0);
        expect(
          find.descendant(
            of: find.byType(EducaBottomNav),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        chat.fail = false;
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
      }
      expect(chat.reads, 1);
      expect(alerts.refreshes, 1);
      expect(
        find.descendant(
          of: find.byType(EducaBottomNav),
          matching: find.textContaining(RegExp(r'^\d+\+?$')),
        ),
        others == 0 ? findsNothing : findsOneWidget,
      );
      chat.arrive();
      await tester.pumpAndSettle();
      expect(
        chat.reads,
        2,
        reason: 'Messages arriving while the chat stays open are read',
      );
      expect(alerts.refreshes, 2);
      expect(chat.unread, 0);
      expect(
        find.descendant(
          of: find.byType(EducaBottomNav),
          matching: find.textContaining(RegExp(r'^\d+\+?$')),
        ),
        others == 0 ? findsNothing : findsOneWidget,
      );
      if (others > 0) {
        expect(
          find.descendant(
            of: find.byType(EducaBottomNav),
            matching: find.text('$others'),
          ),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      chat.dispose();
      router.dispose();
    });
  }
}
