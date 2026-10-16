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
    this.notificationWarning,
    this.requestId,
    this.delivery,
    this.publicationError,
  });

  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String audience;
  final String? notificationWarning;
  final String? requestId;
  final AnnouncementDelivery? delivery;
  final String? publicationError;

  bool get isPublishing =>
      publicationError == null && (delivery?.active ?? false);

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        date,
        audience,
        requestId,
        delivery,
        publicationError,
      ];
}

class AnnouncementDelivery extends Equatable {
  const AnnouncementDelivery({
    required this.status,
    this.phase = 'queued',
    this.total = 0,
    this.processed = 0,
    this.emailed = 0,
    this.emailFailed = 0,
    this.emailSkipped = 0,
  });
  final String status;
  final String phase;
  final int total, processed, emailed, emailFailed, emailSkipped;
  bool get active => ['publishing', 'queued', 'processing'].contains(status);
  bool get canRetry => ['failed', 'completed_with_errors'].contains(status);
  factory AnnouncementDelivery.fromJson(Map<String, dynamic> json) =>
      AnnouncementDelivery(
        status: json['status'] as String,
        phase: json['phase'] as String? ?? 'queued',
        total: (json['total'] as num?)?.toInt() ?? 0,
        processed: (json['processed'] as num?)?.toInt() ?? 0,
        emailed: (json['emailed'] as num?)?.toInt() ?? 0,
        emailFailed: (json['emailFailed'] as num?)?.toInt() ?? 0,
        emailSkipped: (json['emailSkipped'] as num?)?.toInt() ?? 0,
      );
  @override
  List<Object?> get props =>
      [status, phase, total, processed, emailed, emailFailed, emailSkipped];
}
