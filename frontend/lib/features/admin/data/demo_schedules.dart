import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../schedule/data/schedule_mock.dart';
import 'admin_schedule.dart';
import 'school_directory.dart';

/// Horarios en memoria para el modo demo (sin servidor). Mismas reglas de
/// choque que el backend: un grupo, un maestro o un aula no pueden estar en
/// dos bloques a la vez, y un receso choca con lo que ocurra en su grupo.
class DemoSchedulesNotifier extends StateNotifier<List<AdminScheduleEntry>> {
  DemoSchedulesNotifier() : super(_seed());

  int _seq = 1000;

  /// Devuelve el motivo del choque con otro bloque, o `null` si no hay.
  String? conflictFor({
    required int weekdayId,
    required String start,
    required String end,
    required bool isBreak,
    required String? groupId,
    String? teacherId,
    String? room,
    String? ignoreId,
    required SchoolDirectory dir,
  }) {
    final s = _minutes(start);
    final e = _minutes(end);
    for (final o in state) {
      if (o.id == ignoreId || o.weekdayId != weekdayId) continue;
      if (!(s < _minutes(o.endTime) && e > _minutes(o.startTime))) continue;
      final range = '(${o.startTime}–${o.endTime})';
      if (isBreak) {
        if (groupId == null || o.groupId == null || o.groupId == groupId) {
          return 'Choque de horario: se cruza con ${o.subject} $range.';
        }
        continue;
      }
      if (o.isBreak) {
        if (o.groupId == null || o.groupId == groupId) {
          return 'Choque de horario: se cruza con el receso "${o.subject}" '
              '$range.';
        }
        continue;
      }
      if (o.groupId != null && o.groupId == groupId) {
        return 'Choque de horario: el grupo ya tiene ${o.subject} $range.';
      }
      final otherTeacher = dir.classById(o.classId ?? '')?.teacherId;
      if (teacherId != null && otherTeacher == teacherId) {
        return 'Choque de horario: el maestro ya tiene ${o.subject} $range.';
      }
      if (room != null &&
          room.isNotEmpty &&
          (o.room ?? '').toLowerCase() == room.toLowerCase()) {
        return 'Choque de horario: el aula ya está ocupada por ${o.subject} '
            '$range.';
      }
    }
    return null;
  }

  /// Crea un bloque por cada día de [weekdayIds].
  void add({
    required Iterable<int> weekdayIds,
    required bool isBreak,
    required String subject,
    required String startTime,
    required String endTime,
    String? classId,
    String? groupId,
    String? groupName,
    String? teacher,
    String? room,
    String? shift,
  }) {
    state = [
      ...state,
      for (final d in weekdayIds)
        AdminScheduleEntry(
          id: 'demo-${_seq++}',
          kind: isBreak ? 'break' : 'class',
          weekdayId: d,
          startTime: startTime,
          endTime: endTime,
          subject: subject,
          classId: classId,
          groupId: groupId,
          groupName: groupName,
          teacher: teacher,
          room: room,
          shift: shift,
        ),
    ];
  }

  void update(AdminScheduleEntry entry) {
    state = [for (final o in state) o.id == entry.id ? entry : o];
  }

  void remove(String id) {
    state = state.where((o) => o.id != id).toList();
  }

  static int _minutes(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  /// Parte del horario de ejemplo del alumno, para que el módulo no arranque
  /// vacío en demo.
  static List<AdminScheduleEntry> _seed() {
    final out = <AdminScheduleEntry>[];
    ScheduleMock.byDay.forEach((day, slots) {
      for (var i = 0; i < slots.length; i++) {
        final s = slots[i];
        out.add(
          AdminScheduleEntry(
            id: 'demo-$day-$i',
            kind: s.isBreak ? 'break' : 'class',
            weekdayId: day + 1,
            startTime: s.start,
            endTime: s.end,
            subject: s.subject,
            groupId: 'g-4a',
            groupName: '4° Grado A',
            teacher: s.teacher.isEmpty ? null : s.teacher,
            room: s.room.isEmpty ? null : s.room,
            shift: 'morning',
          ),
        );
      }
    });
    return out;
  }
}

final demoSchedulesProvider =
    StateNotifierProvider<DemoSchedulesNotifier, List<AdminScheduleEntry>>(
  (ref) => DemoSchedulesNotifier(),
);
