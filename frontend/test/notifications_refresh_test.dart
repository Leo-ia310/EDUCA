import 'dart:async';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/features/notifications/data/backend_notifications_repository.dart';
import 'package:educa360/features/notifications/domain/entities.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _NotificationsApi extends BackendApiClient {
  _NotificationsApi(SupabaseClient client) : super(supabase: client);
  final calls = <String>[];
  List<int> ids = [1];
  bool fail = false;
  Completer<dynamic>? pending;
  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters,
      bool authenticated = true,}) async {
    calls.add(path);
    if (path == '/auth/2fa/status') return {'enabled': false};
    if (pending != null) return pending!.future;
    if (fail) throw StateError('offline');
    return [
      for (final id in ids)
        {
          'id': '$id',
          'channel': 'message',
          'title': 'Notice $id',
          'body': 'Text',
          'read': false,
          'receivedAt': '2026-10-18T12:00:00Z',
        },
    ];
  }
}

Future<void> _tick([Duration duration = Duration.zero]) =>
    Future<void>.delayed(duration);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late _NotificationsApi api;
  late BackendNotificationsRepository repository;
  setUp(() {
    client = SupabaseClient('https://fixture.supabase.co', 'fixture-public');
    api = _NotificationsApi(client);
    repository = BackendNotificationsRepository(api,
        pollEvery: const Duration(milliseconds: 200),);
  });
  tearDown(() async {
    repository.dispose();
    await client.dispose();
  });

  test(
      'feed and badge share initial read; status is cached and arrivals are not repeated',
      () async {
    final snapshots = <List<AppNotification>>[], arrivals = <AppNotification>[];
    final feed = repository.watchAll().listen(snapshots.add);
    final badge = repository.watchUnread().listen((_) {});
    final arrival = repository.arrivals.listen(arrivals.add);
    await _tick();
    expect(api.calls.where((p) => p == '/notifications').length, 1);
    expect(api.calls.where((p) => p == '/auth/2fa/status').length, 1);
    expect(snapshots.last.any((n) => n.id == 'security-2fa'), isTrue);
    expect(arrivals, isEmpty);
    api.ids = [2];
    await repository.refresh();
    await _tick();
    expect(arrivals.map((n) => n.id), ['2']);
    api.ids = [1, 2];
    await repository.refresh();
    await _tick();
    expect(arrivals.map((n) => n.id), ['2']);
    expect(api.calls.where((p) => p == '/auth/2fa/status').length, 1);
    repository.dispose();
    final count = api.calls.length;
    await _tick(const Duration(milliseconds: 250));
    expect(api.calls.length, count);
    await feed.cancel();
    await badge.cancel();
    await arrival.cancel();
  });

  test(
      'background stops polling, ignores late snapshots and resume refreshes status once',
      () async {
    var items = <AppNotification>[];
    final feed = repository.watchAll().listen((value) => items = value);
    await _tick();
    api.pending = Completer<dynamic>();
    final a = repository.refresh(), b = repository.refresh();
    await _tick();
    final count = api.calls.where((p) => p == '/notifications').length;
    repository.didChangeAppLifecycleState(AppLifecycleState.paused);
    api.pending!.complete([
      {'id': '99', 'title': 'Late'},
    ]);
    await Future.wait([a, b]);
    await _tick();
    expect(items.any((n) => n.id == '99'), isFalse);
    await _tick(const Duration(milliseconds: 450));
    expect(api.calls.where((p) => p == '/notifications').length, count);
    api.pending = null;
    api.ids = [3];
    repository.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await repository.refresh();
    await _tick();
    expect(items.any((n) => n.id == '3'), isTrue);
    expect(api.calls.where((p) => p == '/auth/2fa/status').length, 2);
    await feed.cancel();
  });

  test(
      'network failure preserves the last feed and does not announce old entries on recovery',
      () async {
    await repository.refresh();
    var items = <AppNotification>[];
    final feed = repository.watchAll().listen((value) => items = value);
    final arrivals = <AppNotification>[];
    final arrival = repository.arrivals.listen(arrivals.add);
    await _tick();
    api.fail = true;
    await repository.refresh();
    await _tick();
    expect(items.any((n) => n.id == '1'), isTrue);
    api.fail = false;
    await repository.refresh();
    await _tick();
    expect(arrivals, isEmpty);
    await feed.cancel();
    await arrival.cancel();
  });
}
