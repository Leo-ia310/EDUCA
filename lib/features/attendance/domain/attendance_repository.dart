import 'entities.dart';

/// Contrato de acceso a asistencia (independiente del transporte).
abstract class AttendanceRepository {
  /// Clases que el docente tiene hoy y sobre las que puede pasar lista.
  Future<List<ClassSessionBrief>> todaysClasses({required int teacherId});

  /// Estudiantes inscritos en una clase, junto con la asistencia del día (si ya
  /// fue marcada). Si todavía no hay registros, devuelve cada estudiante con
  /// estado por defecto [AttendanceStatus.present].
  Future<List<({StudentBrief student, AttendanceRecord? record})>>
      classRoster({required int classId, required DateTime date});

  /// Inserta o actualiza un marcado de asistencia.
  /// **Offline-first:** persiste en Hive y devuelve inmediatamente. La
  /// sincronización con Supabase queda a cargo del [AttendanceSyncService].
  Future<AttendanceRecord> upsertRecord(AttendanceRecord record);

  /// Marca el pase de asistencia como finalizado. Crea/actualiza la
  /// `class_sessions` y empuja todos los marcados pendientes a la cola.
  Future<void> finishSession({
    required String sessionUuid,
    required int classId,
    required DateTime date,
    required int teacherId,
  });

  /// Historial de pases (resumen por sesión).
  Future<List<AttendanceSessionSummary>> sessionsHistory({
    int? classId,
    int limit = 50,
  });

  /// Cuántos registros tiene la cola de sincronización pendientes.
  Future<int> pendingCount();
}
