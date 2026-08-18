import '../domain/entities.dart';
import '../domain/schedule_repository.dart';
import 'schedule_mock.dart';

/// Envuelve `ScheduleMock` (hoy consumido directo por `ScheduleScreen`) en la
/// interfaz [ScheduleRepository], para el día en que la pantalla se cablee a
/// través de un provider en vez de leer el mock estático.
class MockScheduleRepository implements ScheduleRepository {
  Future<List<ScheduleSlot>> _weekly() async {
    final slots = <ScheduleSlot>[];
    ScheduleMock.byDay.forEach((day, classSlots) {
      for (final c in classSlots) {
        slots.add(
          ScheduleSlot(
            classId: slots.length,
            weekdayIndex: day,
            startTime: c.start,
            endTime: c.end,
            subjectName: c.subject,
            groupName: '',
            teacherName: c.teacher,
            room: c.room,
          ),
        );
      }
    });
    return slots;
  }

  @override
  Future<List<ScheduleSlot>> weeklyScheduleForStudent(int studentId) => _weekly();

  @override
  Future<List<ScheduleSlot>> weeklyScheduleForTeacher(int teacherId) => _weekly();
}
