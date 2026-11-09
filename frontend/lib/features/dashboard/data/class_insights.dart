import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/supabase_client.dart';
import '../../attendance/domain/entities.dart';
import '../../auth/presentation/auth_controller.dart';

/// Nota mínima aprobatoria de la escala numérica 0–100 por defecto: por debajo
/// de ella (o con asistencia menor a [lowAttendance]) un estudiante se marca
/// «en riesgo».
const passGrade = 60.0;
const lowAttendance = 0.8;

/// Un estudiante de la clase con su asistencia y notas acumuladas.
class StudentInsight {
  const StudentInsight({
    required this.id,
    required this.fullName,
    this.code,
    this.sessions = 0,
    this.present = 0,
    this.late = 0,
    this.absent = 0,
    this.justified = 0,
    this.gradedCount = 0,
    this.gradeAverage,
  });

  final int id;
  final String fullName;
  final String? code;

  /// Marcas de asistencia registradas para este estudiante en la clase.
  final int sessions;
  final int present;
  final int late;
  final int absent;

  /// Justificadas o con permiso.
  final int justified;

  /// Evaluaciones calificadas y promedio sobre 100 (`null` = sin notas).
  final int gradedCount;
  final double? gradeAverage;

  /// Fracción 0–1 de clases a las que asistió (la tardanza cuenta como
  /// asistencia); `null` si aún no hay marcas.
  double? get attendanceRate =>
      sessions == 0 ? null : (present + late + justified) / sessions;

  bool get atRisk =>
      (attendanceRate != null && attendanceRate! < lowAttendance) ||
      (gradeAverage != null && gradeAverage! < passGrade);
}

/// Un bloque semanal de la clase (0 = lunes … 6 = domingo).
class ClassWeekSlot {
  const ClassWeekSlot({
    required this.weekdayIndex,
    required this.start,
    required this.end,
    this.room,
  });

  final int weekdayIndex;
  final String start;
  final String end;
  final String? room;
}

/// Todo lo que muestran el detalle de la clase y la lista de estudiantes.
class ClassInsights {
  const ClassInsights({
    required this.students,
    this.attendanceRate,
    this.gradeAverage,
    this.pendingGrading,
    this.activeAssignments,
    this.slots = const [],
  });

  final List<StudentInsight> students;

  /// Promedio de asistencia / de notas de la clase (`null` = sin datos o sin
  /// permiso para verlos).
  final double? attendanceRate;
  final double? gradeAverage;
  final int? pendingGrading;
  final int? activeAssignments;
  final List<ClassWeekSlot> slots;

  int get atRiskCount => students.where((s) => s.atRisk).length;
}

/// Une matrícula, asistencia y notas en un [StudentInsight] por estudiante.
/// Es una función pura para poder probarla sin red.
List<StudentInsight> buildStudentInsights({
  required List<Map<String, dynamic>> enrollments,
  required List<Map<String, dynamic>> attendances,
  required List<Map<String, dynamic>> grades,
}) {
  final marks = <int, List<int>>{};
  for (final row in attendances) {
    final id = (row['student_id'] as num?)?.toInt();
    final status = (row['attendance_status_id'] as num?)?.toInt();
    if (id == null || status == null) continue;
    (marks[id] ??= []).add(status);
  }
  final percents = <int, List<double>>{};
  for (final row in grades) {
    final id = (row['student_id'] as num?)?.toInt();
    final score = (row['score'] as num?)?.toDouble();
    final max =
        ((row['evaluations'] as Map?)?['max_score'] as num?)?.toDouble() ?? 0;
    if (id == null || score == null || max <= 0) continue;
    (percents[id] ??= []).add(score / max * 100);
  }

  final result = <StudentInsight>[];
  final seen = <int>{};
  for (final row in enrollments) {
    final student = row['students'];
    if (student is! Map) continue;
    final id = (student['id'] as num?)?.toInt();
    if (id == null || !seen.add(id)) continue;
    final person = student['persons'];
    final name = person is Map
        ? '${person['first_name'] ?? ''} ${person['last_name'] ?? ''}'.trim()
        : '';
    var present = 0, late = 0, absent = 0, justified = 0;
    for (final status in marks[id] ?? const <int>[]) {
      switch (AttendanceStatus.fromId(status)) {
        case AttendanceStatus.present:
          present++;
        case AttendanceStatus.late:
          late++;
        case AttendanceStatus.absent:
          absent++;
        case AttendanceStatus.excused:
        case AttendanceStatus.permission:
          justified++;
      }
    }
    final scores = percents[id] ?? const <double>[];
    result.add(
      StudentInsight(
        id: id,
        fullName: name.isEmpty ? 'Estudiante' : name,
        code: student['student_code'] as String?,
        sessions: present + late + absent + justified,
        present: present,
        late: late,
        absent: absent,
        justified: justified,
        gradedCount: scores.length,
        gradeAverage: scores.isEmpty
            ? null
            : scores.reduce((a, b) => a + b) / scores.length,
      ),
    );
  }
  result.sort(
    (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
  );
  return result;
}

/// Bloques semanales de [classId] a partir de las filas de `/schedules/mine`.
List<ClassWeekSlot> classSlotsFrom(Object? schedules, int classId) {
  if (schedules is! List) return const [];
  final slots = <ClassWeekSlot>[];
  for (final raw in schedules) {
    if (raw is! Map || raw['kind'] != 'class') continue;
    if (int.tryParse('${raw['classId']}') != classId) continue;
    final day = (raw['weekdayIndex'] as num?)?.toInt();
    if (day == null) continue;
    slots.add(
      ClassWeekSlot(
        weekdayIndex: day,
        start: '${raw['startTime'] ?? ''}',
        end: '${raw['endTime'] ?? ''}',
        room: raw['room'] == null ? null : '${raw['room']}',
      ),
    );
  }
  slots.sort((a, b) {
    final byDay = a.weekdayIndex.compareTo(b.weekdayIndex);
    return byDay != 0 ? byDay : a.start.compareTo(b.start);
  });
  return slots;
}

/// La próxima clase del horario a partir de [now]: el bloque y a cuántos días
/// está (0 = hoy). Un bloque de hoy que ya terminó pasa a la semana siguiente.
({ClassWeekSlot slot, int daysAhead})? nextClassSlot(
  List<ClassWeekSlot> slots,
  DateTime now,
) {
  int minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  final today = now.weekday - 1; // 0 = lunes
  final nowMin = now.hour * 60 + now.minute;
  ({ClassWeekSlot slot, int daysAhead})? best;
  for (final slot in slots) {
    var ahead = (slot.weekdayIndex - today + 7) % 7;
    final end = minutes(slot.end.isEmpty ? slot.start : slot.end);
    if (ahead == 0 && end <= nowMin) ahead = 7;
    final better = best == null ||
        ahead < best.daysAhead ||
        (ahead == best.daysAhead &&
            minutes(slot.start) < minutes(best.slot.start));
    if (better) best = (slot: slot, daysAhead: ahead);
  }
  return best;
}

Future<List<Map<String, dynamic>>> _allPages(
  Future<List<Map<String, dynamic>>> Function(int from, int to) page,
) async {
  // PostgREST entrega 1000 filas por consulta como máximo.
  final out = <Map<String, dynamic>>[];
  for (var from = 0; from < 20000; from += 1000) {
    final rows = await page(from, from + 999);
    out.addAll(rows);
    if (rows.length < 1000) break;
  }
  return out;
}

/// Estudiantes de la clase con su asistencia y promedio, más el resumen de la
/// clase (tareas, por calificar, horario). Cada dato opcional que no se pueda
/// leer (p. ej. un colaborador sin ese permiso) queda en `null` sin romper el
/// resto.
final classInsightsProvider =
    FutureProvider.autoDispose.family<ClassInsights, int>((ref, classId) async {
  final client = ref.watch(supabaseClientProvider);
  final api = ref.watch(backendApiClientProvider);
  final institutionId = ref.watch(
    authControllerProvider.select((a) => a.user?.institutionId),
  );
  if (client == null || institutionId == null) {
    throw StateError('Se requiere conexión para consultar la clase.');
  }

  Future<T?> optional<T>(Future<T> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return null;
    }
  }

  final cls = await client
      .from('classes')
      .select('group_id')
      .eq('id', classId)
      .single();
  final groupId = (cls['group_id'] as num).toInt();

  // Solo estudiantes activos, matriculados (ACT) en el año actual.
  final enrollments = await client
      .from('enrollments')
      .select(
        'students!inner(id, active, student_code, persons(first_name, last_name)),'
        'academic_years!inner(is_current),catalog_enrollment_statuses!inner(code)',
      )
      .eq('institution_id', institutionId)
      .eq('students.active', true)
      .eq('academic_years.is_current', true)
      .eq('catalog_enrollment_statuses.code', 'ACT')
      .eq('group_id', groupId);

  final results = await Future.wait<Object?>([
    optional(
      () => _allPages(
        (from, to) => client
            .from('attendances')
            .select(
                'student_id, attendance_status_id, class_sessions!inner(class_id)',)
            .eq('class_sessions.class_id', classId)
            .order('id')
            .range(from, to),
      ),
    ),
    optional(
      () => _allPages(
        (from, to) => client
            .from('grades')
            .select('student_id, score, evaluations!inner(class_id, max_score)')
            .eq('evaluations.class_id', classId)
            .not('score', 'is', null)
            .order('id')
            .range(from, to),
      ),
    ),
    optional(
      () async => (await client.rpc(
        'dashboard_pending_grading',
        params: {
          'p_class_ids': [classId],
        },
      ) as num)
          .toInt(),
    ),
    optional(
      () async => (await client
              .from('assignments')
              .select('id, due_at')
              .eq('class_id', classId)
              .eq('published', true)
              .gte('due_at', DateTime.now().toUtc().toIso8601String()) as List)
          .length,
    ),
    optional(() async {
      final data = await api?.get('/schedules/mine');
      return classSlotsFrom(data is Map ? data['schedules'] : null, classId);
    }),
  ]);

  final attendances = results[0] as List<Map<String, dynamic>>?;
  final grades = results[1] as List<Map<String, dynamic>>?;
  final students = buildStudentInsights(
    enrollments: [
      for (final row in enrollments as List)
        Map<String, dynamic>.from(row as Map),
    ],
    attendances: attendances ?? const [],
    grades: grades ?? const [],
  );

  double? mean(Iterable<double> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

  return ClassInsights(
    students: students,
    attendanceRate: attendances == null
        ? null
        : mean(
            students.map((s) => s.attendanceRate).whereType<double>(),
          ),
    gradeAverage: grades == null
        ? null
        : mean(students.map((s) => s.gradeAverage).whereType<double>()),
    pendingGrading: results[2] as int?,
    activeAssignments: results[3] as int?,
    slots: (results[4] as List<ClassWeekSlot>?) ?? const [],
  );
});
