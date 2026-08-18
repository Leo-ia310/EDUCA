import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Un anuncio o evento institucional. En modo demo vive en memoria; con
/// Supabase real correspondería a la tabla `announcements` / `events`.
class SchoolEvent {
  const SchoolEvent({
    required this.title,
    required this.description,
    required this.date,
    required this.audience,
    this.icon = Icons.campaign_outlined,
  });

  final String title;
  final String description;
  final DateTime date;
  final String audience;
  final IconData icon;
}

/// Store en memoria de anuncios/eventos. Es **singleton** vía provider para
/// que los eventos creados en el formulario se reflejen en la lista.
class EventsStore extends StateNotifier<List<SchoolEvent>> {
  EventsStore() : super(_seed);

  static final List<SchoolEvent> _seed = [
    SchoolEvent(
      title: 'Reunión de Padres Trimestral',
      description:
          'Discusión sobre nuevos lineamientos de tecnología y plan de becas 2026.',
      date: DateTime.now().add(const Duration(days: 3)),
      audience: 'Padres y tutores',
      icon: Icons.groups_outlined,
    ),
    SchoolEvent(
      title: 'Feria de Ciencias 2026',
      description:
          'Convocatoria abierta a estudiantes para presentar proyectos.',
      date: DateTime.now().add(const Duration(days: 12)),
      audience: 'Toda la institución',
      icon: Icons.science_outlined,
    ),
    SchoolEvent(
      title: 'Mantenimiento de Servidores',
      description:
          'El portal EduCore estará fuera de servicio el sábado por la noche.',
      date: DateTime.now().add(const Duration(days: 5)),
      audience: 'Toda la institución',
      icon: Icons.build_outlined,
    ),
  ];

  void add(SchoolEvent event) {
    state = [event, ...state];
  }
}

final eventsStoreProvider =
    StateNotifierProvider<EventsStore, List<SchoolEvent>>((ref) {
  return EventsStore();
});
