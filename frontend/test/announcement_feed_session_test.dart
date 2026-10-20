import 'dart:async';
import 'package:educa360/features/events/data/mock_events_repository.dart';
import 'package:educa360/features/events/domain/entities.dart';
import 'package:educa360/features/events/presentation/announcement_feed_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

SchoolEvent event(String id, {AnnouncementDelivery? delivery}) => SchoolEvent(
      id: id,
      title: id,
      description: 'Contenido',
      date: DateTime(2026),
      audience: 'all',
      delivery: delivery,
    );

class Repository extends MockEventsRepository {
  final signals = StreamController<AnnouncementSignal>.broadcast();
  final cursors = <String?>[];
  var first = AnnouncementPage([event('3'), event('2')],
      hasMore: true, nextBeforeId: '2',);
  var older = AnnouncementPage([event('2'), event('1')]);
  bool failMore = false;
  int progressCalls = 0;
  Completer<AnnouncementPage>? moreGate;
  Map<String, AnnouncementDelivery?> statuses = {};
  @override
  Stream<AnnouncementSignal> watchInvalidations() => signals.stream;
  @override
  Future<AnnouncementPage> publishedPage(
      {String? beforeId, int limit = 50,}) async {
    cursors.add(beforeId);
    if (beforeId == null) return first;
    if (failMore) throw StateError('sin red');
    return moreGate == null ? older : moreGate!.future;
  }

  @override
  Future<Map<String, AnnouncementDelivery?>> progress(List<String> ids) async {
    progressCalls++;
    return {for (final id in ids) id: statuses[id]};
  }
}

void main() {
  testWidgets(
      'page retry preserves cursor, deduplicates and offers new head without skipping older rows',
      (tester) async {
    final repo = Repository();
    final session = AnnouncementFeedSession(repo, random: () => .5);
    final subscription = session.watch().listen((_) {});
    await tester.pump();
    repo.failMore = true;
    await session.loadMore();
    expect(session.state.moreError, isNotNull);
    expect(session.state.items.map((e) => e.id), ['3', '2']);
    repo.failMore = false;
    await session.loadMore();
    expect(session.state.items.map((e) => e.id), ['3', '2', '1']);
    expect(repo.cursors, [null, '2', '2']);
    repo.first = AnnouncementPage([event('4'), event('3')],
        hasMore: true, nextBeforeId: '3',);
    repo.signals
        .add(const AnnouncementSignal(AnnouncementSignalKind.publication));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 151));
    expect(session.state.hasNewItems, isTrue);
    expect(session.state.items.map((e) => e.id), ['3', '2', '1']);
    await session.reload();
    expect(session.state.items.map((e) => e.id), ['4', '3']);
    expect(session.state.hasNewItems, isFalse);
    session.dispose();
    unawaited(subscription.cancel());
    unawaited(repo.signals.close());
    await tester.pump();
  });

  testWidgets(
      'active delivery polling reads metadata only and ignores older versions',
      (tester) async {
    final repo = Repository();
    final latest = AnnouncementDelivery(
        status: 'processing',
        processed: 5,
        updatedAt: DateTime.utc(2026, 10, 2),);
    repo.first = AnnouncementPage([event('1', delivery: latest)]);
    repo.statuses = {
      '1': AnnouncementDelivery(
          status: 'processing',
          processed: 2,
          updatedAt: DateTime.utc(2026, 10, 1),),
    };
    final session = AnnouncementFeedSession(repo, random: () => .5);
    final subscription = session.watch().listen((_) {});
    await tester.pump();
    expect(session.state.items.single.delivery!.processed, 5);
    expect(repo.cursors.length, 1);
    expect(repo.progressCalls, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(repo.progressCalls, 2);
    expect(repo.cursors.length, 1);
    repo.statuses = {
      '1': AnnouncementDelivery(
          status: 'completed',
          processed: 10,
          updatedAt: DateTime.utc(2026, 10, 3),),
    };
    await tester.pump(const Duration(seconds: 2));
    expect(session.state.items.single.delivery!.status, 'completed');
    final count = repo.progressCalls;
    await tester.pump(const Duration(seconds: 10));
    expect(repo.progressCalls, count);
    session.dispose();
    unawaited(subscription.cancel());
    unawaited(repo.signals.close());
    await tester.pump();
  });

  testWidgets(
      'background and disposal stop refreshes and ignore late page responses',
      (tester) async {
    final repo = Repository();
    final session = AnnouncementFeedSession(repo, random: () => .5);
    final subscription = session.watch().listen((_) {});
    await tester.pump();
    repo.moreGate = Completer<AnnouncementPage>();
    final pending = session.loadMore();
    session.didChangeAppLifecycleState(AppLifecycleState.paused);
    repo.signals
        .add(const AnnouncementSignal(AnnouncementSignalKind.publication));
    await tester.pump(const Duration(minutes: 1));
    expect(repo.cursors.length, 2);
    session.dispose();
    repo.moreGate!.complete(AnnouncementPage([event('1')]));
    await pending;
    expect(session.state.items.map((e) => e.id), ['3', '2']);
    unawaited(subscription.cancel());
    unawaited(repo.signals.close());
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));
    expect(repo.cursors.length, 2);
  });

  testWidgets('explicit refresh invalidates an older page already in flight',
      (tester) async {
    final repo = Repository();
    final session = AnnouncementFeedSession(repo, random: () => .5);
    final subscription = session.watch().listen((_) {});
    await tester.pump();
    repo.moreGate = Completer<AnnouncementPage>();
    final pending = session.loadMore();
    repo.first = AnnouncementPage([event('9')]);
    await session.reload();
    repo.moreGate!.complete(AnnouncementPage([event('1')]));
    await pending;
    expect(session.state.items.single.id, '9');
    expect(session.state.loadingMore, isFalse);
    session.dispose();
    unawaited(subscription.cancel());
    unawaited(repo.signals.close());
    await tester.pump();
  });
}
