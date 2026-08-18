import 'package:equatable/equatable.dart';

/// Bloque de horario de una clase. Puramente datos — el mapeo a
/// color/ícono por materia es responsabilidad de la presentación (ver
/// `data/schedule_mock.dart`, que hoy alimenta la UI directamente).
class ScheduleSlot extends Equatable {
  const ScheduleSlot({
    required this.classId,
    required this.weekdayIndex,
    required this.startTime,
    required this.endTime,
    required this.subjectName,
    required this.groupName,
    this.teacherName,
    this.room,
  });

  final int classId;

  /// 0 = Lunes .. 6 = Domingo (coincide con `ScheduleMock.days`, que solo
  /// usa 0-4).
  final int weekdayIndex;

  /// `HH:mm`.
  final String startTime;
  final String endTime;
  final String subjectName;
  final String groupName;
  final String? teacherName;
  final String? room;

  @override
  List<Object?> get props => [classId, weekdayIndex, startTime, endTime];
}
