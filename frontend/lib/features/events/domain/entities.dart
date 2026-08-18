import 'package:equatable/equatable.dart';

/// Evento o anuncio institucional. Puramente datos — el ícono que usa
/// `EventsStore`/`SchoolEvent` (mock) es una decoración de presentación, no
/// algo que viva en `calendar_events`.
class SchoolEvent extends Equatable {
  const SchoolEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.audience,
  });

  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String audience;

  @override
  List<Object?> get props => [id, title, date, audience];
}
