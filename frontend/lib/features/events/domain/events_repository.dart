import 'entities.dart';

/// Acceso a eventos/anuncios institucionales.
///
abstract class EventsRepository {
  Future<List<SchoolEvent>> upcoming();

  Future<SchoolEvent> create({
    required String title,
    required String description,
    required DateTime date,
    required String audience,
  });
}
