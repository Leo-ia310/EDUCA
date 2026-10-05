import 'package:flutter/foundation.dart';

/// Tipo de entrada del calendario escolar.
enum CalKind { event, task }

@immutable
class CalItem {
  const CalItem({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.kind,
  });

  final DateTime date;
  final String title;
  final String subtitle;
  final CalKind kind;
}

/// Eventos escolares + tareas próximas (mock demo), relativos a hoy y ordenados
/// por fecha. Compartido entre el calendario escolar y el resumen del home.
List<CalItem> schoolCalendarItems([DateTime? from]) {
  final now = from ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime d(int addDays) => today.add(Duration(days: addDays));
  return <CalItem>[
    CalItem(date: d(1), title: 'Entrega: Ensayo de Ética', subtitle: 'Ética', kind: CalKind.task),
    CalItem(date: d(2), title: 'Feria de Ciencias', subtitle: 'Evento escolar · Patio central', kind: CalKind.event),
    CalItem(date: d(4), title: 'Entrega: Práctica de Ecuaciones', subtitle: 'Matemáticas Avanzadas', kind: CalKind.task),
    CalItem(date: d(6), title: 'Reunión de padres', subtitle: 'Evento escolar · Auditorio', kind: CalKind.event),
    CalItem(date: d(9), title: 'Examen Parcial II', subtitle: 'Matemáticas Avanzadas', kind: CalKind.task),
    CalItem(date: d(12), title: 'Salida pedagógica', subtitle: 'Evento escolar · Museo', kind: CalKind.event),
    CalItem(date: d(15), title: 'Entrega: Revolución Industrial', subtitle: 'Historia Universal', kind: CalKind.task),
    CalItem(date: d(20), title: 'Día del estudiante', subtitle: 'Evento escolar', kind: CalKind.event),
  ]..sort((a, b) => a.date.compareTo(b.date));
}
