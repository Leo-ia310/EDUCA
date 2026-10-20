import 'dart:async';
import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/domain/auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:educa360/features/chat/providers.dart';
import 'package:educa360/features/events/data/mock_events_repository.dart';
import 'package:educa360/features/events/domain/entities.dart';
import 'package:educa360/features/events/presentation/screens/announcements_screen.dart';
import 'package:educa360/features/events/presentation/screens/create_event_screen.dart';
import 'package:educa360/features/events/providers.dart';
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
        institution: Institution(id: 2, code: 'TEST', name: 'Test'),
        user: AppUser(
          id: '5',
          institutionId: 2,
          email: 'admin@demo.com',
          fullName: 'Admin',
          roles: [AppRole.admin],
          activeRole: AppRole.admin,
        ),
      );
}

class _Events extends MockEventsRepository {
  bool listFails = false;
  bool saveFails = false;
  Completer<void>? saveGate;
  final requestIds = <String?>[];
  int listCalls = 0;
  final rows = <SchoolEvent>[];

  @override
  Future<List<SchoolEvent>> published() async {
    listCalls++;
    if (listFails) throw StateError('API no disponible');
    return List.of(rows);
  }

  @override
  Future<SchoolEvent> create({
    required String title,
    required String description,
    required DateTime date,
    required String audience,
    String? requestId,
  }) async {
    requestIds.add(requestId);
    if (saveGate != null) await saveGate!.future;
    if (saveFails) throw StateError('No se pudo guardar');
    final saved = SchoolEvent(
      id: '1',
      title: title,
      description: description,
      date: date,
      audience: audience,
      requestId: requestId,
    );
    rows.add(saved);
    return saved;
  }
}

GoRouter _router() => GoRouter(
      initialLocation: '/announcements',
      routes: [
        GoRoute(
          path: '/announcements',
          builder: (_, __) => const AnnouncementsScreen(),
        ),
        GoRoute(
          path: '/events/new',
          builder: (_, __) => const CreateEventScreen(),
        ),
      ],
    );

Widget _app(_Events repository, GoRouter router) => ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_AdminAuth()),
        eventsRepositoryProvider.overrideWithValue(repository),
        totalUnreadProvider.overrideWith((ref) => Stream.value(0)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  testWidgets(
      'review-only deliveries show their state without offering a blind resend',
      (tester) async {
    final repo = _Events();
    repo.rows.add(
      SchoolEvent(
        id: 'review',
        title: 'Aviso en revisión',
        description: 'Contenido',
        date: DateTime(2026),
        audience: 'all',
        delivery: const AnnouncementDelivery(
          status: 'completed_with_errors',
          total: 1,
          processed: 1,
          emailFailed: 1,
          emailReview: 1,
        ),
      ),
    );
    final router = _router();
    await tester.pumpWidget(_app(repo, router));
    await tester.pumpAndSettle();
    expect(find.text('Publicado · correos por revisar: 1'), findsOneWidget);
    expect(find.text('Reintentar envío'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
      'a push failure remains retryable when the email requires separate review',
      () {
    final delivery = AnnouncementDelivery.fromJson(const {
      'status': 'completed_with_errors',
      'total': 1,
      'processed': 1,
      'emailFailed': 1,
      'emailReview': 1,
      'pushFailed': 1,
    });
    expect(delivery.canRetry, isTrue);
    expect(delivery.emailReview, 1);
    expect(delivery.pushFailed, 1);
  });
  testWidgets(
      'refreshes a cached empty list on return and polls external publications',
      (tester) async {
    final repo = _Events();
    final router = _router();
    await tester.pumpWidget(_app(repo, router));
    await tester.pumpAndSettle();
    expect(find.text('Sin anuncios'), findsOneWidget);
    router.push('/events/new');
    await tester.pumpAndSettle();
    repo.rows.add(
      SchoolEvent(
        id: '10',
        title: 'Publicado desde otra sesión',
        description: 'Guardado real',
        date: DateTime(2026),
        audience: 'all',
      ),
    );
    router.pop();
    await tester.pumpAndSettle();
    // This route can remain mounted under the form, so polling also refreshes it.
    await tester.pump(const Duration(seconds: 36));
    await tester.pumpAndSettle();
    expect(find.text('Publicado desde otra sesión'), findsOneWidget);
    expect(find.text('Sin anuncios'), findsNothing);
    repo.rows.add(
      SchoolEvent(
        id: '11',
        title: 'Segundo aviso externo',
        description: 'Otro aviso',
        date: DateTime(2026),
        audience: 'all',
      ),
    );
    await tester.pump(const Duration(seconds: 36));
    await tester.pumpAndSettle();
    expect(find.text('Segundo aviso externo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
  testWidgets(
      'listing failure shows an error and retry, with no mock or empty fallback',
      (tester) async {
    final repo = _Events()..listFails = true;
    final router = _router();
    await tester.pumpWidget(_app(repo, router));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No se pudieron cargar los anuncios'),
      findsOneWidget,
    );
    expect(find.text('Sin anuncios'), findsNothing);
    expect(find.text('Reunión de Padres Trimestral'), findsNothing);
    repo.listFails = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Sin anuncios'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
  for (final failsFirst in [false, true]) {
    testWidgets('publication appears immediately after save; retry=$failsFirst',
        (tester) async {
      final repo = _Events()..saveFails = failsFirst;
      final router = _router();
      await tester.pumpWidget(_app(repo, router));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Nuevo anuncio'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Anuncio persistido',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Contenido del anuncio',
      );
      final publish = find.text('Publicar anuncio');
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.pumpAndSettle();
      if (failsFirst) {
        expect(repo.rows, isEmpty);
        expect(
          find.textContaining('No se pudo publicar el anuncio'),
          findsOneWidget,
        );
        expect(find.text('Crear anuncio'), findsNothing);
        repo.saveFails = false;
        await tester.tap(find.text('Reintentar publicación'));
        await tester.pumpAndSettle();
        expect(repo.requestIds[0], repo.requestIds[1]);
      }
      expect(repo.rows, hasLength(1));
      expect(repo.listCalls, greaterThanOrEqualTo(2));
      expect(find.text('Anuncio persistido'), findsOneWidget);
      expect(find.text('Contenido del anuncio'), findsOneWidget);
      expect(find.text('Sin anuncios'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    });
  }

  testWidgets(
      'closes form while request is pending and keeps progress across navigation',
      (tester) async {
    final gate = Completer<void>();
    final repo = _Events()..saveGate = gate;
    final router = _router();
    await tester.pumpWidget(_app(repo, router));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Nuevo anuncio'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'En segundo plano',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Contenido pendiente',
    );
    await tester.ensureVisible(find.text('Publicar anuncio'));
    await tester.tap(find.text('Publicar anuncio'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Crear anuncio'), findsNothing);
    expect(find.text('Publicando…'), findsOneWidget);
    expect(find.text('En segundo plano'), findsOneWidget);
    expect(repo.rows, isEmpty);
    // The user can open another form while the first publication continues.
    await tester.tap(find.byTooltip('Nuevo anuncio'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Crear anuncio'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Publicado'), findsOneWidget);
    expect(find.text('En segundo plano'), findsOneWidget);
    expect(repo.rows, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
}
