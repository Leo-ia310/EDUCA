import 'package:uuid/uuid.dart';

import '../domain/entities.dart';
import '../domain/events_repository.dart';

const _uuid = Uuid();

/// Espejo en memoria de la semilla de `EventsStore`, para completar el par
/// mock/Supabase de [EventsRepository] (hoy sin consumidor — ver la nota en
/// `domain/events_repository.dart`).
class MockEventsRepository implements EventsRepository {
  final List<SchoolEvent> _events = [
    SchoolEvent(
      id: _uuid.v4(),
      title: 'Reunión de Padres Trimestral',
      description:
          'Discusión sobre nuevos lineamientos de tecnología y plan de becas 2026.',
      date: DateTime.now().add(const Duration(days: 3)),
      audience: 'Padres y tutores',
    ),
    SchoolEvent(
      id: _uuid.v4(),
      title: 'Feria de Ciencias 2026',
      description: 'Convocatoria abierta a estudiantes para presentar proyectos.',
      date: DateTime.now().add(const Duration(days: 12)),
      audience: 'Toda la institución',
    ),
    SchoolEvent(
      id: _uuid.v4(),
      title: 'Mantenimiento de Servidores',
      description:
          'El portal EduCore estará fuera de servicio el sábado por la noche.',
      date: DateTime.now().add(const Duration(days: 5)),
      audience: 'Toda la institución',
    ),
  ];

  @override
  Future<List<SchoolEvent>> upcoming() async => List.unmodifiable(_events);

  @override
  Future<SchoolEvent> create({
    required String title,
    required String description,
    required DateTime date,
    required String audience,
  }) async {
    final event = SchoolEvent(
      id: _uuid.v4(),
      title: title,
      description: description,
      date: date,
      audience: audience,
    );
    _events.insert(0, event);
    return event;
  }
}
