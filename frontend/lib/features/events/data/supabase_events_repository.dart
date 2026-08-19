import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/backend_api_client.dart';
import '../domain/entities.dart';
import '../domain/events_repository.dart';

/// Implementación real contra Supabase. Tabla usada (ver
/// `supabase/migrations/0001_init_core.sql`): `calendar_events`.
class SupabaseEventsRepository implements EventsRepository {
  SupabaseEventsRepository({
    required SupabaseClient client,
    required BackendApiClient api,
    required this.institutionId,
  })  : _c = client,
        _api = api;

  final SupabaseClient _c;
  final BackendApiClient _api;
  final int institutionId;

  static const _select = 'id, title, description, start_at, audience';

  @override
  Future<List<SchoolEvent>> upcoming() async {
    final rows = await _c
        .from('calendar_events')
        .select(_select)
        .eq('institution_id', institutionId)
        .order('start_at');
    return (rows as List).cast<Map<String, dynamic>>().map(_fromRow).toList();
  }

  @override
  Future<SchoolEvent> create({
    required String title,
    required String description,
    required DateTime date,
    required String audience,
  }) async {
    final response = await _api.call('events.create', {
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'audience': audience,
    });
    final data = Map<String, dynamic>.from(response as Map);
    return _fromApi(Map<String, dynamic>.from(data['event'] as Map));
  }

  SchoolEvent _fromRow(Map<String, dynamic> row) => SchoolEvent(
        id: row['id'].toString(),
        title: row['title'] as String? ?? '',
        description: row['description'] as String? ?? '',
        date: DateTime.tryParse(row['start_at'] as String? ?? '') ??
            DateTime.now(),
        audience: row['audience'] as String? ?? 'Toda la institución',
      );

  SchoolEvent _fromApi(Map<String, dynamic> row) => SchoolEvent(
        id: row['id'].toString(),
        title: row['title'] as String? ?? '',
        description: row['description'] as String? ?? '',
        date: DateTime.tryParse(row['date'] as String? ?? '') ?? DateTime.now(),
        audience: row['audience'] as String? ?? 'Toda la institución',
      );
}
