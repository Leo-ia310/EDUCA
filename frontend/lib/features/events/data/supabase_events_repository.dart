import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/network/backend_api_client.dart';
import '../domain/entities.dart';
import '../domain/events_repository.dart';

/// Published announcements are read and written through the authenticated API.
/// The backend resolves the institution, author and audience from the session.
class SupabaseEventsRepository extends EventsRepository {
  SupabaseEventsRepository({
    required BackendApiClient api,
    SupabaseClient? realtime,
    this.institutionId,
    this.userId,
    this.admin = false,
  })  : _api = api,
        _realtime = realtime;
  final SupabaseClient? _realtime;
  final int? institutionId;
  final String? userId;
  final bool admin;

  final BackendApiClient _api;

  @override
  Future<List<SchoolEvent>> published() async => (await publishedPage()).items;

  @override
  Future<AnnouncementPage> publishedPage({
    String? beforeId,
    int limit = 50,
  }) async {
    final response = await _api.get(
      '/events/announcements',
      queryParameters: {'beforeId': beforeId, 'limit': limit},
    );
    final data = Map<String, dynamic>.from(response as Map);
    return AnnouncementPage(
      (data['announcements'] as List)
          .map((row) => _fromApi(Map<String, dynamic>.from(row as Map)))
          .toList(),
      hasMore: data['hasMore'] == true,
      nextBeforeId: data['nextBeforeId']?.toString(),
    );
  }

  @override
  Future<Map<String, AnnouncementDelivery?>> progress(List<String> ids) async {
    final result = <String, AnnouncementDelivery?>{};
    for (var start = 0; start < ids.length; start += 100) {
      final batch = ids.skip(start).take(100).toList();
      final response = await _api.get(
        '/events/announcements/status',
        queryParameters: {'ids': batch.join(',')},
      );
      final data = Map<String, dynamic>.from(response as Map);
      for (final id in batch) {
        result[id] = null;
      }
      for (final row in data['deliveries'] as List) {
        result[row['announcementId'].toString()] =
            AnnouncementDelivery.fromJson(
          Map<String, dynamic>.from(row['delivery'] as Map),
        );
      }
    }
    return result;
  }

  @override
  Stream<AnnouncementSignal> watchInvalidations() {
    final client = _realtime;
    if (client == null || institutionId == null || userId == null) {
      return const Stream.empty();
    }
    RealtimeChannel? channel;
    var canceled = false;
    late final StreamController<AnnouncementSignal> controller;
    void emit(AnnouncementSignal signal) {
      if (!canceled && !controller.isClosed) controller.add(signal);
    }

    controller = StreamController<AnnouncementSignal>(
      onListen: () {
        try {
          channel = client
              .channel(
                'announcements:$institutionId:$userId:${identityHashCode(controller)}',
              )
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'announcements',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'institution_id',
                  value: institutionId!,
                ),
                callback: (_) => emit(
                  const AnnouncementSignal(
                    AnnouncementSignalKind.publication,
                  ),
                ),
              )
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'announcement_delivery_jobs',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: admin ? 'institution_id' : 'created_by',
                  value: admin ? institutionId! : userId!,
                ),
                callback: (_) => emit(
                  const AnnouncementSignal(AnnouncementSignalKind.progress),
                ),
              )
              .subscribe(
                (status, error) => emit(
                  AnnouncementSignal(
                    AnnouncementSignalKind.connection,
                    healthy: status == RealtimeSubscribeStatus.subscribed,
                  ),
                ),
              );
        } catch (_) {
          emit(const AnnouncementSignal(AnnouncementSignalKind.connection));
        }
      },
      onCancel: () async {
        canceled = true;
        final existing = channel;
        if (existing != null) await client.removeChannel(existing);
      },
    );
    return controller.stream;
  }

  @override
  Future<SchoolEvent> create({
    required String title,
    required String description,
    required DateTime date,
    required String audience,
    String? requestId,
  }) async {
    final response = await _api.call('events.create', {
      'title': title,
      'description': description,
      'date': date.toUtc().toIso8601String(),
      'audience': _audienceCode(audience),
      if (requestId != null) 'requestId': requestId,
    });
    final data = Map<String, dynamic>.from(response as Map);
    final announcement = Map<String, dynamic>.from(data['announcement'] as Map);
    return _fromApi({
      ...announcement,
      'notificationWarning': data['notificationWarning'],
    });
  }

  SchoolEvent _fromApi(Map<String, dynamic> row) => SchoolEvent(
        id: row['id'].toString(),
        title: row['title'] as String,
        description: row['description'] as String,
        date: DateTime.parse(row['date'] as String).toLocal(),
        audience: row['audience'] as String,
        notificationWarning: row['notificationWarning'] as String?,
        requestId: row['requestId'] as String?,
        delivery: row['delivery'] == null
            ? null
            : AnnouncementDelivery.fromJson(
                Map<String, dynamic>.from(row['delivery'] as Map),
              ),
      );

  @override
  Future<void> retryDelivery(String announcementId) async {
    await _api.post('/events/announcements/$announcementId/retry-delivery');
  }

  String _audienceCode(String label) => switch (label) {
        'Toda la institución' => 'all',
        'Padres y tutores' => 'parents',
        'Estudiantes' => 'students',
        'Docentes' => 'teachers',
        'Administración' => 'staff',
        _ => label,
      };
}
