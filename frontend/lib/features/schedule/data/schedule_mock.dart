import 'package:flutter/material.dart';

/// Bloque de horario para un día concreto.
class ClassSlot {
  const ClassSlot({
    required this.start,
    required this.end,
    required this.subject,
    required this.room,
    required this.teacher,
    required this.icon,
    required this.color,
    this.isBreak = false,
  });

  final String start;
  final String end;
  final String subject;
  final String room;
  final String teacher;
  final IconData icon;
  final Color color;

  /// Receso (sin maestro ni aula).
  final bool isBreak;
}

/// Horario semanal de demostración, indexado por día (0 = Lunes .. 4 = Viernes).
class ScheduleMock {
  ScheduleMock._();

  static const days = <String>['Lun', 'Mar', 'Mié', 'Jue', 'Vie'];
  static const daysLong = <String>[
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
  ];

  static const _mate = Color(0xFF3B82F6);
  static const _hist = Color(0xFFF59E0B);
  static const _fis = Color(0xFF8B5CF6);
  static const _bio = Color(0xFF10B981);
  static const _lit = Color(0xFFEC4899);

  static const _pool = <ClassSlot>[
    ClassSlot(
      start: '',
      end: '',
      subject: 'Matemáticas Avanzadas',
      room: 'Aula 402',
      teacher: 'Prof. Ricardo Méndez',
      icon: Icons.calculate_rounded,
      color: _mate,
    ),
    ClassSlot(
      start: '',
      end: '',
      subject: 'Historia Universal',
      room: 'Aula 108',
      teacher: 'Lic. Roberto Díaz',
      icon: Icons.account_balance_rounded,
      color: _hist,
    ),
    ClassSlot(
      start: '',
      end: '',
      subject: 'Física Cuántica',
      room: 'Lab. 25',
      teacher: 'Dra. Elena Ruiz',
      icon: Icons.science_rounded,
      color: _fis,
    ),
    ClassSlot(
      start: '',
      end: '',
      subject: 'Biología Celular',
      room: 'Lab. 12',
      teacher: 'Prof. Elena Santís',
      icon: Icons.biotech_rounded,
      color: _bio,
    ),
    ClassSlot(
      start: '',
      end: '',
      subject: 'Literatura',
      room: 'Aula 210',
      teacher: 'Lic. Marta Solís',
      icon: Icons.menu_book_rounded,
      color: _lit,
    ),
  ];

  /// Cada día: 4 clases (rotando las materias) con un receso a media mañana.
  static final Map<int, List<ClassSlot>> byDay = {
    for (var d = 0; d < 5; d++)
      d: () {
        ClassSlot at(int k, String start, String end) {
          final b = _pool[(d + k) % _pool.length];
          return ClassSlot(
            start: start,
            end: end,
            subject: b.subject,
            room: b.room,
            teacher: b.teacher,
            icon: b.icon,
            color: b.color,
          );
        }

        return <ClassSlot>[
          at(0, '08:00', '09:30'),
          at(1, '09:45', '11:15'),
          const ClassSlot(
            start: '11:15',
            end: '11:45',
            subject: 'Receso',
            room: '',
            teacher: '',
            icon: Icons.free_breakfast_rounded,
            color: Color(0xFF64748B),
            isBreak: true,
          ),
          at(2, '11:45', '13:15'),
          at(3, '13:30', '15:00'),
        ];
      }(),
  };

  /// Índice del día laboral actual (0-4). Sábado/Domingo caen a Lunes.
  static int todayIndex() {
    final weekday = DateTime.now().weekday; // 1=Lun .. 7=Dom
    if (weekday >= 6) return 0;
    return weekday - 1;
  }
}
