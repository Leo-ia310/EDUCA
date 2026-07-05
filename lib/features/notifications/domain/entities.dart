import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Canal / categoría de notificación. Mapea a `catalog_notification_types`
/// del backend y a los Android notification channels (uno por categoría
/// para que el usuario pueda silenciar por tipo desde Ajustes del sistema).
enum NotificationChannel {
  message('message', 'Mensajes', 'Mensajes del chat', Icons.chat_bubble_outline),
  task('task', 'Tareas', 'Nuevas tareas o vencimientos', Icons.assignment_outlined),
  grade('grade', 'Calificaciones', 'Notas publicadas', Icons.grade_outlined),
  attendance('attendance', 'Asistencia', 'Ausencias y avisos', Icons.event_available_outlined),
  announcement('announcement', 'Comunicados', 'Avisos institucionales', Icons.campaign_outlined),
  payment('payment', 'Pagos', 'Cargos y recibos', Icons.payments_outlined),
  system('system', 'Sistema', 'Alertas técnicas', Icons.info_outlined);

  const NotificationChannel(this.code, this.title, this.description, this.icon);
  final String code;
  final String title;
  final String description;
  final IconData icon;

  static NotificationChannel fromCode(String? code) {
    if (code == null) return NotificationChannel.system;
    for (final c in NotificationChannel.values) {
      if (c.code == code) return c;
    }
    return NotificationChannel.system;
  }
}

/// Prioridad. Influye en si se muestra heads-up en Android.
enum NotificationPriority {
  low,
  normal,
  high,
  urgent;

  bool get isHeadsUp => this == high || this == urgent;
}

/// Notificación tal como se persiste en el feed de la app.
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.channel,
    required this.title,
    required this.body,
    required this.receivedAt,
    required this.priority,
    required this.read,
    this.data = const {},
    this.deepLink,
    this.iconOverride,
  });

  final String id;
  final NotificationChannel channel;
  final String title;
  final String body;
  final DateTime receivedAt;
  final NotificationPriority priority;
  final bool read;

  /// Payload arbitrario que llega desde FCM (`data` de la mensajería).
  final Map<String, dynamic> data;

  /// Ruta destino del deep-link (ej. `/assignments/a-mat-002`).
  final String? deepLink;

  final IconData? iconOverride;

  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      channel: channel,
      title: title,
      body: body,
      receivedAt: receivedAt,
      priority: priority,
      read: read ?? this.read,
      data: data,
      deepLink: deepLink,
      iconOverride: iconOverride,
    );
  }

  @override
  List<Object?> get props => [id, read, receivedAt];
}
