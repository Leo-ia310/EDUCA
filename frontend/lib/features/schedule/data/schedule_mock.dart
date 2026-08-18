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
  });

  final String start;
  final String end;
  final String subject;
  final String room;
  final String teacher;
  final IconData icon;
  final Color color;
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

  static const Map<int, List<ClassSlot>> byDay = {
    0: [
      ClassSlot(
        start: '08:00',
        end: '09:30',
        subject: 'Matemáticas Avanzadas',
        room: 'Aula 402',
        teacher: 'Prof. Ricardo Méndez',
        icon: Icons.calculate_outlined,
        color: _mate,
      ),
      ClassSlot(
        start: '09:45',
        end: '11:15',
        subject: 'Historia Universal',
        room: 'Aula 108',
        teacher: 'Lic. Roberto Díaz',
        icon: Icons.account_balance_outlined,
        color: _hist,
      ),
      ClassSlot(
        start: '11:30',
        end: '13:00',
        subject: 'Física Cuántica',
        room: 'Lab. 25',
        teacher: 'Dra. Elena Ruiz',
        icon: Icons.science_outlined,
        color: _fis,
      ),
    ],
    1: [
      ClassSlot(
        start: '08:00',
        end: '09:30',
        subject: 'Biología Celular',
        room: 'Lab. 12',
        teacher: 'Prof. Elena Santís',
        icon: Icons.biotech_outlined,
        color: _bio,
      ),
      ClassSlot(
        start: '09:45',
        end: '11:15',
        subject: 'Literatura',
        room: 'Aula 210',
        teacher: 'Lic. Marta Solís',
        icon: Icons.menu_book_outlined,
        color: _lit,
      ),
    ],
    2: [
      ClassSlot(
        start: '08:00',
        end: '09:30',
        subject: 'Matemáticas Avanzadas',
        room: 'Aula 402',
        teacher: 'Prof. Ricardo Méndez',
        icon: Icons.calculate_outlined,
        color: _mate,
      ),
      ClassSlot(
        start: '09:45',
        end: '11:15',
        subject: 'Física Cuántica',
        room: 'Lab. 25',
        teacher: 'Dra. Elena Ruiz',
        icon: Icons.science_outlined,
        color: _fis,
      ),
      ClassSlot(
        start: '11:30',
        end: '13:00',
        subject: 'Historia Universal',
        room: 'Aula 108',
        teacher: 'Lic. Roberto Díaz',
        icon: Icons.account_balance_outlined,
        color: _hist,
      ),
    ],
    3: [
      ClassSlot(
        start: '08:00',
        end: '09:30',
        subject: 'Literatura',
        room: 'Aula 210',
        teacher: 'Lic. Marta Solís',
        icon: Icons.menu_book_outlined,
        color: _lit,
      ),
      ClassSlot(
        start: '09:45',
        end: '11:15',
        subject: 'Biología Celular',
        room: 'Lab. 12',
        teacher: 'Prof. Elena Santís',
        icon: Icons.biotech_outlined,
        color: _bio,
      ),
    ],
    4: [
      ClassSlot(
        start: '08:00',
        end: '09:30',
        subject: 'Matemáticas Avanzadas',
        room: 'Aula 402',
        teacher: 'Prof. Ricardo Méndez',
        icon: Icons.calculate_outlined,
        color: _mate,
      ),
      ClassSlot(
        start: '09:45',
        end: '11:15',
        subject: 'Historia Universal',
        room: 'Aula 108',
        teacher: 'Lic. Roberto Díaz',
        icon: Icons.account_balance_outlined,
        color: _hist,
      ),
    ],
  };

  /// Índice del día laboral actual (0-4). Sábado/Domingo caen a Lunes.
  static int todayIndex() {
    final weekday = DateTime.now().weekday; // 1=Lun .. 7=Dom
    if (weekday >= 6) return 0;
    return weekday - 1;
  }
}
