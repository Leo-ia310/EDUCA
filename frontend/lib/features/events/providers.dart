import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/supabase_client.dart';
import '../auth/presentation/auth_controller.dart';
import 'data/mock_events_repository.dart';
import 'data/supabase_events_repository.dart';
import 'domain/events_repository.dart';

/// Listo para cuando `AnnouncementsScreen`/`CreateEventScreen` se cableen a
/// datos reales — ver el comentario en `domain/events_repository.dart`. Hoy
/// nada consume este provider todavía (siguen usando `eventsStoreProvider`).
final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final client = ref.watch(supabaseClientProvider);
  if (client == null || auth.institution == null) {
    return MockEventsRepository();
  }
  return SupabaseEventsRepository(
    client: client,
    institutionId: auth.institution!.id,
  );
});
