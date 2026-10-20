import 'entities.dart';

/// Acceso a eventos/anuncios institucionales.
///
abstract class EventsRepository {
  Future<List<SchoolEvent>> published();

  Future<AnnouncementPage> publishedPage({
    String? beforeId,
    int limit = 50,
  }) async {
    final rows = await published();
    final start =
        beforeId == null ? 0 : rows.indexWhere((e) => e.id == beforeId) + 1;
    final items = rows.skip(start).take(limit).toList();
    final more = start + items.length < rows.length;
    return AnnouncementPage(
      items,
      hasMore: more,
      nextBeforeId: more && items.isNotEmpty ? items.last.id : null,
    );
  }

  Future<Map<String, AnnouncementDelivery?>> progress(List<String> ids) async {
    final rows = await published();
    return {
      for (final id in ids)
        id: rows.where((e) => e.id == id).firstOrNull?.delivery,
    };
  }

  Stream<AnnouncementSignal> watchInvalidations() => const Stream.empty();

  Future<SchoolEvent> create({
    required String title,
    required String description,
    required DateTime date,
    required String audience,
    String? requestId,
  });

  Future<void> retryDelivery(String announcementId);
}
