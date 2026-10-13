import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/backend_api_client.dart';
import '../../core/network/supabase_client.dart';
import '../auth/presentation/auth_controller.dart';
import 'data/events_store.dart' as view;
import 'data/mock_events_repository.dart';
import 'data/supabase_events_repository.dart';
import 'domain/entities.dart' as domain;
import 'domain/events_repository.dart';

/// Repositorio de anuncios/eventos. En modo conectado persiste en backend;
/// en demo mantiene estado en memoria durante la sesión.
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

/// Eventos próximos para la lista (`AnnouncementsScreen`).
final upcomingEventsViewProvider =
    FutureProvider<List<view.SchoolEvent>>((ref) async {
  final repo = ref.watch(eventsRepositoryProvider);
  final events = await repo.upcoming();
  return events.map(_toViewEvent).toList();
});

view.SchoolEvent _toViewEvent(domain.SchoolEvent event) => view.SchoolEvent(
      title: event.title,
      description: event.description,
      date: event.date,
      audience: _audienceLabel(event.audience),
      icon: _eventIcon(event.audience),
    );

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
      return Icons.groups_rounded;
    case 'academic':
      return Icons.school_rounded;
    case 'drill':
      return Icons.warning_amber_rounded;
    case 'holiday':
      return Icons.celebration_rounded;
    case 'sport':
      return Icons.sports_soccer_rounded;
    default:
      return Icons.campaign_rounded;
  }
}
