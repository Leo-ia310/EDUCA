import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities.dart';
import '../domain/events_repository.dart';

/// Implementación real contra Supabase. Tabla usada (ver
/// `backend/migrations/0001_init_core.sql`): `calendar_events`.
class SupabaseEventsRepository implements EventsRepository {
  SupabaseEventsRepository({
    required SupabaseClient client,
    required this.institutionId,
  }) : _c = client;

  final SupabaseClient _c;
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
    final row = await _c
        .from('calendar_events')
        .insert({
          'institution_id': institutionId,
          'title': title,
          'description': description,
          'start_at': date.toIso8601String(),
          'audience': audience,
          'type': 'event',
        })
        .select(_select)
        .single();
    return _fromRow(row);
  }

  SchoolEvent _fromRow(Map<String, dynamic> row) => SchoolEvent(
        id: row['id'].toString(),
        title: row['title'] as String? ?? '',
        description: row['description'] as String? ?? '',
        date: DateTime.tryParse(row['start_at'] as String? ?? '') ?? DateTime.now(),
        audience: row['audience'] as String? ?? 'Toda la institución',
      );
}
