import '../portal_access/providers.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/env.dart';
import '../../core/network/backend_api_client.dart';
import '../../core/network/supabase_client.dart';
import '../auth/presentation/auth_controller.dart';
import '../dashboard/providers.dart';
import 'data/mock_events_repository.dart';
import 'data/supabase_events_repository.dart';
import 'domain/entities.dart' as domain;
import 'domain/events_repository.dart';

/// Repositorio de anuncios/eventos. En modo conectado persiste en backend;
/// en demo mantiene estado en memoria durante la sesión.
final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  ref.watch(portalFingerprintProvider);
  final auth = ref.watch(authControllerProvider);
  final client = ref.watch(supabaseClientProvider);
  final api = ref.watch(backendApiClientProvider);
  if (Env.isDemoMode) {
    return MockEventsRepository();
  }
  if (client == null ||
      api == null ||
      auth.institution == null ||
      auth.user == null) {
    throw StateError('Inicia sesión para consultar o publicar anuncios.');
  }
  return SupabaseEventsRepository(api: api);
});

/// Server state is independent of optimistic drafts, which survive navigation.
final announcementsProvider =
    FutureProvider<List<domain.SchoolEvent>>((ref) async {
  return ref.watch(eventsRepositoryProvider).published();
});

final announcementPublisherProvider =
    StateNotifierProvider<AnnouncementPublisher, List<domain.SchoolEvent>>(
        (ref) {
  ref.watch(authControllerProvider.select((auth) => auth.user?.id));
  return AnnouncementPublisher(ref);
});

class AnnouncementPublisher extends StateNotifier<List<domain.SchoolEvent>> {
  AnnouncementPublisher(this.ref) : super([]);
  final Ref ref;

  void submit({
    required String title,
    required String description,
    required DateTime date,
    required String audience,
  }) {
    final id = const Uuid().v4();
    final draft = domain.SchoolEvent(
      id: id,
      requestId: id,
      title: title,
      description: description,
      date: date,
      audience: audience,
      delivery: const domain.AnnouncementDelivery(status: 'publishing'),
    );
    state = [draft, ...state];
    unawaited(_publish(draft));
  }

  void retry(domain.SchoolEvent event) {
    final draft = domain.SchoolEvent(
      id: event.id,
      requestId: event.requestId,
      title: event.title,
      description: event.description,
      date: event.date,
      audience: event.audience,
      delivery: const domain.AnnouncementDelivery(status: 'publishing'),
    );
    state = [
      for (final e in state)
        if (e.id == event.id) draft else e,
    ];
    unawaited(_publish(draft));
  }

  void reconcile(List<domain.SchoolEvent> saved) {
    state = state
        .where(
          (draft) => !saved.any(
            (row) =>
                row.id == draft.id ||
                (row.requestId != null && row.requestId == draft.requestId),
          ),
        )
        .toList();
  }

  Future<void> _publish(domain.SchoolEvent draft) async {
    try {
      final saved = await ref.read(eventsRepositoryProvider).create(
            title: draft.title,
            description: draft.description,
            date: draft.date,
            audience: draft.audience,
            requestId: draft.requestId,
          );
      if (!mounted) return;
      state = [
        for (final e in state)
          if (e.id == draft.id) saved else e,
      ];
      ref.invalidate(announcementsProvider);
      ref.invalidate(adminDashboardProvider);
      ref.invalidate(teacherDashboardProvider);
      ref.invalidate(studentDashboardProvider);
      ref.invalidate(parentDashboardProvider);
    } catch (error) {
      if (!mounted) return;
      state = [
        for (final e in state)
          if (e.id == draft.id)
            domain.SchoolEvent(
              id: draft.id,
              requestId: draft.requestId,
              title: draft.title,
              description: draft.description,
              date: draft.date,
              audience: draft.audience,
              publicationError:
                  'No se pudo publicar el anuncio. ${error is StateError ? error.message : error}',
            )
          else
            e,
      ];
    }
  }
}
