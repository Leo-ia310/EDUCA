import 'package:equatable/equatable.dart';

/// Turnos escolares (`schedules.shift`).
const scheduleShifts = <(String code, String label)>[
  ('morning', 'Mañana'),
  ('afternoon', 'Tarde'),
  ('evening', 'Noche'),
];

/// Días de la semana (`weekday_id` 1 = lunes … 7 = domingo).
const scheduleWeekdays = <(int id, String short, String label)>[
  (1, 'Lun', 'Lunes'),
  (2, 'Mar', 'Martes'),
  (3, 'Mié', 'Miércoles'),
  (4, 'Jue', 'Jueves'),
  (5, 'Vie', 'Viernes'),
  (6, 'Sáb', 'Sábado'),
  (7, 'Dom', 'Domingo'),
];

String weekdayLabel(int id) => scheduleWeekdays
    .firstWhere((d) => d.$1 == id, orElse: () => (id, '$id', '$id'))
    .$3;

String shiftLabel(String? code) => scheduleShifts
    .firstWhere((s) => s.$1 == code, orElse: () => ('', ''))
    .$2;

/// Bloque de horario administrado por el admin: una clase en un día y tramo
/// horario, o un receso (de un grupo o de toda la institución).
class AdminScheduleEntry extends Equatable {
  const AdminScheduleEntry({
    required this.id,
    required this.kind,
    required this.weekdayId,
    required this.startTime,
    required this.endTime,
    required this.subject,
    this.classId,
    this.groupId,
    this.groupName,
    this.teacher,
    this.room,
    this.shift,
  });

  factory AdminScheduleEntry.fromJson(Map<String, dynamic> json) =>
      AdminScheduleEntry(
        id: '${json['id']}',
        kind: '${json['kind'] ?? 'class'}',
        weekdayId: (json['weekdayId'] as num).toInt(),
        startTime: '${json['startTime'] ?? ''}',
        endTime: '${json['endTime'] ?? ''}',
        subject: '${json['subject'] ?? ''}',
        classId: json['classId']?.toString(),
        groupId: json['groupId']?.toString(),
        groupName: json['groupName'] as String?,
        teacher: json['teacher'] as String?,
        room: json['room'] as String?,
        shift: json['shift'] as String?,
      );

  final String id;

  /// `class` o `break`.
  final String kind;
  final int weekdayId;

  /// `HH:mm`.
  final String startTime;
  final String endTime;

  /// Materia (clase) o nombre del receso.
  final String subject;
  final String? classId;
  final String? groupId;
  final String? groupName;
  final String? teacher;
  final String? room;
  final String? shift;

  bool get isBreak => kind == 'break';

  @override
  List<Object?> get props => [
        id,
        kind,
        weekdayId,
        startTime,
        endTime,
        subject,
        classId,
        groupId,
        room,
        shift,
      ];
}
