import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/features/events/data/supabase_events_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api implements BackendApiClient {
  bool fail = false;
  String? lastPath;
  final queries = <Map<String, dynamic>>[];
  Map<String, dynamic>? lastPayload;
  final Map<String, dynamic> announcement = {
    'id': '17',
    'title': 'Aviso guardado',
    'description': 'Contenido',
    'date': '2000-01-01T00:00:00Z',
    'audience': 'students',
  };

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    lastPath = path;
    queries.add(queryParameters ?? {});
    if (path.endsWith('/status')) {
      return {
        'deliveries': [
          for (final id in queryParameters!['ids'].toString().split(','))
            {
              'announcementId': id,
              'delivery': {
                'status': 'completed',
                'updatedAt': '2026-10-19T00:00:00Z',
              },
            },
        ],
      };
    }
    if (fail) throw StateError('API no disponible');
    return {
      'announcements': [announcement],
      'hasMore': true,
      'nextBeforeId': '17',
    };
  }

  @override
  Future<dynamic> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (fail) throw StateError('No se pudo guardar');
    lastPath = action;
    lastPayload = payload;
    return {
      'announcement': announcement,
      'notificationWarning': 'Publicado; correo pendiente.',
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('reads published announcements from API, including past dates',
      () async {
    final api = _Api();
    final repo = SupabaseEventsRepository(api: api);
    final rows = await repo.published();
    expect(api.lastPath, '/events/announcements');
    expect(rows.single.id, '17');
    expect(rows.single.date.toUtc().year, 2000);
    expect(rows.single.audience, 'students');
  });
  test(
      'creates through backend and preserves the saved announcement and warning',
      () async {
    final api = _Api();
    final result = await SupabaseEventsRepository(api: api).create(
      title: 'Aviso',
      description: 'Contenido',
      date: DateTime(2026),
      audience: 'Estudiantes',
      requestId: '91e22546-46c6-4cb8-89fb-643d9488d218',
    );
    expect(api.lastPath, 'events.create');
    expect(api.lastPayload?['audience'], 'students');
    expect(
      api.lastPayload?['requestId'],
      '91e22546-46c6-4cb8-89fb-643d9488d218',
    );
    expect(api.lastPayload?.containsKey('institutionId'), false);
    expect(result.id, '17');
    expect(result.notificationWarning, 'Publicado; correo pendiente.');
  });
  test('parses durable progress and failed delivery counts', () async {
    final api = _Api();
    api.announcement['delivery'] = {
      'status': 'processing',
      'phase': 'email',
      'total': 12,
      'processed': 5,
      'emailed': 3,
      'emailFailed': 1,
      'emailSkipped': 1,
    };
    final row = (await SupabaseEventsRepository(api: api).published()).single;
    expect(row.isPublishing, true);
    expect(row.delivery!.processed, 5);
    expect(row.delivery!.emailFailed, 1);
  });
  test('passes cursor without numeric rounding and batches progress by 100 IDs',
      () async {
    final api = _Api();
    final repo = SupabaseEventsRepository(api: api);
    final page = await repo.publishedPage(beforeId: '9007199254740993');
    expect(api.queries.single['beforeId'], '9007199254740993');
    expect(page.nextBeforeId, '17');
    expect(page.hasMore, isTrue);
    final states = await repo.progress(List.generate(205, (i) => '${i + 1}'));
    expect(
        api.queries.skip(1).map((q) => q['ids'].toString().split(',').length),
        [100, 100, 5],);
    expect(states.length, 205);
    expect(states['205']!.updatedAt, DateTime.utc(2026, 10, 19));
  });
  test('API failures propagate instead of becoming an empty list', () async {
    final api = _Api()..fail = true;
    final repo = SupabaseEventsRepository(api: api);
    await expectLater(repo.published(), throwsStateError);
    await expectLater(
      repo.create(
        title: 'Aviso',
        description: 'Texto',
        date: DateTime(2026),
        audience: 'all',
      ),
      throwsStateError,
    );
  });
}
