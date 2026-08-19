import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/backend_api_client.dart';
import '../../core/network/supabase_client.dart';
import '../auth/presentation/auth_controller.dart';
import 'data/events_store.dart';
import 'data/mock_events_repository.dart';
import 'data/supabase_events_repository.dart';
import 'domain/events_repository.dart';

/// Listo para cuando `AnnouncementsScreen`/`CreateEventScreen` se cableen a
/// datos reales — ver el comentario en `domain/events_repository.dart`. Hoy
/// nada consume este provider todavía (siguen usando `eventsStoreProvider`).
final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final client = ref.watch(supabaseClientProvider);
  final api = ref.watch(backendApiClientProvider);
  if (client == null || api == null || auth.institution == null) {
    return MockEventsRepository();
  }
  return SupabaseEventsRepository(
    client: client,
    api: api,
    institutionId: auth.institution!.id,
  );
});

/// Eventos próximos para la lista (`AnnouncementsScreen`). En modo conectado
/// lee la tabla real `calendar_events`; en demo usa el store en memoria.
final upcomingEventsViewProvider =
    FutureProvider<List<SchoolEvent>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authControllerProvider);
  if (client == null || auth.institution == null) {
    return ref.watch(eventsStoreProvider);
  }
  final rows = await client
      .from('calendar_events')
      .select('title, description, start_at, audience, type')
      .eq('institution_id', auth.institution!.id)
      .gte('start_at',
          DateTime.now().subtract(const Duration(days: 1)).toIso8601String())
      .order('start_at');
  return (rows as List).map((r) {
    final m = r as Map<String, dynamic>;
    return SchoolEvent(
      title: m['title'] as String? ?? 'Evento',
      description: m['description'] as String? ?? '',
      date: DateTime.tryParse(m['start_at'] as String? ?? '') ?? DateTime.now(),
      audience: _audienceLabel(m['audience'] as String?),
      icon: _eventIcon(m['type'] as String?),
    );
  }).toList();
});

String _audienceLabel(String? code) {
  switch (code) {
    case 'parents':
      return 'Padres y tutores';
    case 'students':
      return 'Estudiantes';
    case 'teachers':
      return 'Docentes';
    default:
      return 'Toda la institución';
  }
}

IconData _eventIcon(String? type) {
  switch (type) {
    case 'meeting':
      return Icons.groups_outlined;
    case 'academic':
      return Icons.school_outlined;
    case 'drill':
      return Icons.warning_amber_outlined;
    case 'holiday':
      return Icons.celebration_outlined;
    case 'sport':
      return Icons.sports_soccer_outlined;
    default:
      return Icons.campaign_outlined;
  }
}
