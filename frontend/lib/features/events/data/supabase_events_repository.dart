import '../../../core/network/backend_api_client.dart';
import '../domain/entities.dart';
import '../domain/events_repository.dart';

/// Published announcements are read and written through the authenticated API.
/// The backend resolves the institution, author and audience from the session.
class SupabaseEventsRepository implements EventsRepository {
  SupabaseEventsRepository({required BackendApiClient api}) : _api = api;

  final BackendApiClient _api;

  @override
  Future<List<SchoolEvent>> published() async {
    final response = await _api.get('/events/announcements');
    final data = Map<String, dynamic>.from(response as Map);
    return (data['announcements'] as List)
        .map((row) => _fromApi(Map<String, dynamic>.from(row as Map)))
        .toList();
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
