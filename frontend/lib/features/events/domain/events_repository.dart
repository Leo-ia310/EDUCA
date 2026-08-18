import 'entities.dart';

/// Acceso a eventos/anuncios institucionales.
///
/// NOTA para quien cablee esto en presentación: hoy `AnnouncementsScreen` y
/// `CreateEventScreen` leen/escriben directo en `eventsStoreProvider`
/// (`data/events_store.dart`, en memoria), sin pasar por esta interfaz.
/// Cuando se quiera persistir de verdad, hay que crear un `providers.dart`
/// que exponga [EventsRepository] (mock/Supabase, mismo patrón que
/// `assignments`/`chat`) y hacer que esas pantallas lo consuman en vez del
/// store en memoria.
abstract class EventsRepository {
  Future<List<SchoolEvent>> upcoming();

  Future<SchoolEvent> create({
    required String title,
    required String description,
    required DateTime date,
    required String audience,
  });
}
