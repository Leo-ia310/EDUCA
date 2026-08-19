import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities.dart';
import '../domain/schedule_repository.dart';

/// Implementación real contra Supabase. Tablas usadas (ver
/// `supabase/migrations/0001_init_core.sql`): `schedules`, `classes`,
/// `catalog_weekdays`, `classrooms`.
class SupabaseScheduleRepository implements ScheduleRepository {
  SupabaseScheduleRepository({
    required SupabaseClient client,
    required this.institutionId,
  }) : _c = client;

  final SupabaseClient _c;
  final int institutionId;

  static const _scheduleSelect =
      'class_id, start_time, end_time, classroom_id, '
      'catalog_weekdays(display_order), classrooms(name), '
      'classes(subjects(name), groups(name), teachers(persons(first_name, last_name)))';

  @override
  Future<List<ScheduleSlot>> weeklyScheduleForStudent(int studentId) async {
    final enrollments = await _c
        .from('enrollments')
        .select('group_id')
        .eq('student_id', studentId)
        .eq('institution_id', institutionId);
    final groupIds = (enrollments as List)
        .map((e) => (e['group_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();
    if (groupIds.isEmpty) return const [];
    final classes = await _c
        .from('classes')
        .select('id')
        .inFilter('group_id', groupIds)
        .eq('institution_id', institutionId);
    final classIds = (classes as List).map((c) => (c['id'] as num).toInt()).toList();
    return _scheduleForClassIds(classIds);
  }

  @override
  Future<List<ScheduleSlot>> weeklyScheduleForTeacher(int teacherId) async {
    final classes = await _c
        .from('classes')
        .select('id')
        .eq('teacher_id', teacherId)
        .eq('institution_id', institutionId);
    final classIds = (classes as List).map((c) => (c['id'] as num).toInt()).toList();
    return _scheduleForClassIds(classIds);
  }

  Future<List<ScheduleSlot>> _scheduleForClassIds(List<int> classIds) async {
    if (classIds.isEmpty) return const [];
    final rows = await _c
        .from('schedules')
        .select(_scheduleSelect)
        .inFilter('class_id', classIds)
        .eq('institution_id', institutionId);
    final slots =
        (rows as List).cast<Map<String, dynamic>>().map(_slotFromRow).toList();
    slots.sort((a, b) {
      final byDay = a.weekdayIndex.compareTo(b.weekdayIndex);
      return byDay != 0 ? byDay : a.startTime.compareTo(b.startTime);
    });
    return slots;
  }

  ScheduleSlot _slotFromRow(Map<String, dynamic> row) {
    final cls = row['classes'] as Map<String, dynamic>?;
    final subjectName = (cls?['subjects'] as Map?)?['name'] as String? ?? 'Materia';
    final groupName = (cls?['groups'] as Map?)?['name'] as String? ?? '';
    final person = (cls?['teachers'] as Map?)?['persons'] as Map?;
    final teacherName =
        person == null ? null : '${person['first_name'] ?? ''} ${person['last_name'] ?? ''}'.trim();
    final displayOrder = (row['catalog_weekdays'] as Map?)?['display_order'] as int?;
    return ScheduleSlot(
      classId: (row['class_id'] as num).toInt(),
      weekdayIndex: (displayOrder ?? 1) - 1,
      startTime: _formatTime(row['start_time'] as String?),
      endTime: _formatTime(row['end_time'] as String?),
      subjectName: subjectName,
      groupName: groupName,
      teacherName: (teacherName == null || teacherName.isEmpty) ? null : teacherName,
      room: (row['classrooms'] as Map?)?['name'] as String?,
    );
  }

  String _formatTime(String? raw) {
    if (raw == null) return '';
    // Postgres `time` llega como 'HH:mm:ss' — recortar a 'HH:mm'.
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }
}
