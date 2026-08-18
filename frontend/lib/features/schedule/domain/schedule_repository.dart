import 'entities.dart';

/// Acceso al horario semanal de clases.
///
/// NOTA para quien cablee esto en presentación: hoy `ScheduleScreen` lee
/// `data/schedule_mock.dart` directamente, sin pasar por un provider ni por
/// esta interfaz. Cuando se quiera conectar a datos reales, hay que crear un
/// `providers.dart` que exponga [ScheduleRepository] (mock/Supabase, mismo
/// patrón que `assignments`/`chat`) y hacer que la pantalla lo consuma en vez
/// de `ScheduleMock`.
abstract class ScheduleRepository {
  Future<List<ScheduleSlot>> weeklyScheduleForStudent(int studentId);
  Future<List<ScheduleSlot>> weeklyScheduleForTeacher(int teacherId);
}
