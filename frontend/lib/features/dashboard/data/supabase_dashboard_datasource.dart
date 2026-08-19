import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/dashboard_models.dart';
import 'dashboard_data.dart';
import 'mock_dashboard_data.dart';

/// Fuente de datos del dashboard contra Supabase. El frontend solo lee; la
/// lógica y las restricciones viven en el backend (RLS + resolvers + vistas).
class SupabaseDashboardDatasource {
  SupabaseDashboardDatasource(this._c, this.institutionId);

  final SupabaseClient _c;
  final int institutionId;

  // ---------------------------------------------------------------- Estudiante
  Future<StudentDashboardData> studentData(int studentId) async {
    final classIds = await _classIdsForStudent(studentId);
    if (classIds.isEmpty) return StudentDashboardData.empty();

    final results = await Future.wait([
      _classesInfo(classIds),
      _todaySchedule(classIds),
      _studentAssignments(classIds, studentId),
      _studentGrades(studentId),
      _weightedAverage(studentId),
      _classmates(studentId),
    ]);

    final classes = results[0] as List<_ClassInfo>;
    final schedule = results[1] as List<ScheduleSlot>;
    final tasks = results[2] as List<TaskBrief>;
    final grades = results[3] as List<GradeBrief>;
    final avg = results[4] as double;
    final classmates = results[5] as List<String>;

    final subjects = classes
        .map((c) => SubjectProgress(
              name: c.subject,
              teacher: c.teacher ?? 'Docente',
              progress: (avg / 100).clamp(0, 1).toDouble(),
              icon: iconForSubject(c.subject),
            ))
        .toList();

    final pending = tasks.where((t) => t.status == TaskStatus.pending).length;

    return StudentDashboardData(
      pendingTasks: pending,
      todaySchedule: schedule,
      subjects: subjects,
      tasks: tasks,
      grades: grades,
      averageScore: double.parse((avg / 10).toStringAsFixed(1)),
      classmates: classmates.take(4).toList(),
      classmatesExtra: classmates.length > 4 ? classmates.length - 4 : 0,
    );
  }

  // ------------------------------------------------------------------ Docente
  Future<TeacherDashboardData> teacherData(int teacherId) async {
    final classRows = await _c
        .from('classes')
        .select('id, group_id, subjects(name), groups(name)')
        .eq('teacher_id', teacherId)
        .eq('institution_id', institutionId);
    final classes = (classRows as List).cast<Map<String, dynamic>>();
    if (classes.isEmpty) return TeacherDashboardData.empty();

    final classIds =
        classes.map((c) => (c['id'] as num).toInt()).toList();
    final groupIds = classes
        .map((c) => (c['group_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();

    final results = await Future.wait([
      _teacherAssignments(classIds, groupIds),
      _teacherRecentGrades(classIds),
      _todaySchedule(classIds),
      _teacherPendingGrading(classIds),
      _teacherRoster(groupIds),
    ]);

    final myClasses = classes
        .map((c) => TeacherClass(
              name: (c['subjects'] as Map?)?['name'] as String? ?? 'Clase',
              room: (c['groups'] as Map?)?['name'] as String? ?? '',
              icon: iconForSubject(
                  (c['subjects'] as Map?)?['name'] as String? ?? ''),
            ))
        .toList();

    return TeacherDashboardData(
      quickAttendance: results[4] as List<AttendanceLine>,
      myClasses: myClasses,
      upcomingAssignments: results[0] as List<UpcomingAssignment>,
      recentGrades: results[1] as List<RecentGrade>,
      pendingClasses: (results[2] as List<ScheduleSlot>).length,
      pendingGrading: results[3] as int,
    );
  }

  Future<List<UpcomingAssignment>> _teacherAssignments(
      List<int> classIds, List<int> groupIds) async {
    final rows = await _c
        .from('assignments')
        .select('id, title, due_at, class_id, classes(groups(name))')
        .inFilter('class_id', classIds)
        .filter('deleted_at', 'is', null)
        .order('due_at')
        .limit(6);
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return const [];

    final totalByGroup = <int, int>{};
    for (final g in groupIds) {
      final enr =
          await _c.from('enrollments').select('id').eq('group_id', g);
      totalByGroup[g] = (enr as List).length;
    }
    final ids = list.map((a) => (a['id'] as num).toInt()).toList();
    final subs = await _c
        .from('submissions')
        .select('assignment_id')
        .inFilter('assignment_id', ids);
    final deliveredBy = <int, int>{};
    for (final s in (subs as List)) {
      final aid = (s['assignment_id'] as num).toInt();
      deliveredBy[aid] = (deliveredBy[aid] ?? 0) + 1;
    }

    final now = DateTime.now();
    return list.map((a) {
      final group =
          ((a['classes'] as Map?)?['groups'] as Map?)?['name'] as String? ??
              'Grupo';
      final due = DateTime.tryParse(a['due_at'] as String? ?? '');
      final aid = (a['id'] as num).toInt();
      final delivered = deliveredBy[aid] ?? 0;
      final total = groupIds.isEmpty ? 0 : (totalByGroup.values.first);
      final urgent =
          due != null && due.difference(now).inDays <= 1 && due.isAfter(now);
      final completed = total > 0 && delivered >= total;
      final meta = due == null
          ? 'Sin fecha · $group'
          : 'Límite: ${_shortDate(due)} · $group';
      return UpcomingAssignment(
        title: a['title'] as String? ?? 'Tarea',
        meta: meta,
        delivered: delivered,
        total: total,
        urgent: urgent,
        completed: completed,
      );
    }).toList();
  }

  Future<List<RecentGrade>> _teacherRecentGrades(List<int> classIds) async {
    final evalRows = await _c
        .from('evaluations')
        .select('id, title')
        .inFilter('class_id', classIds);
    final evalTitles = {
      for (final e in (evalRows as List))
        (e['id'] as num).toInt(): e['title'] as String? ?? 'Evaluación',
    };
    if (evalTitles.isEmpty) return const [];
    final rows = await _c
        .from('grades')
        .select(
            'score, evaluation_id, created_at, students(persons(first_name, last_name)), evaluations(max_score)')
        .inFilter('evaluation_id', evalTitles.keys.toList())
        .not('score', 'is', null)
        .order('created_at', ascending: false)
        .limit(5);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final person =
          (m['students'] as Map?)?['persons'] as Map<String, dynamic>?;
      final name =
          '${person?['first_name'] ?? ''} ${person?['last_name'] ?? ''}'.trim();
      final max = ((m['evaluations'] as Map?)?['max_score'] as num?)?.toDouble() ??
          100;
      final raw = (m['score'] as num?)?.toDouble() ?? 0;
      final title = evalTitles[(m['evaluation_id'] as num).toInt()] ?? '';
      return RecentGrade(
        name.isEmpty ? 'Estudiante' : name,
        'Tema: $title',
        double.parse((max == 0 ? 0.0 : raw / max * 10).toStringAsFixed(1)),
        _relativeWhen(DateTime.tryParse(m['created_at'] as String? ?? '')),
      );
    }).toList();
  }

  Future<int> _teacherPendingGrading(List<int> classIds) async {
    final assigns = await _c
        .from('assignments')
        .select('id')
        .inFilter('class_id', classIds)
        .filter('deleted_at', 'is', null);
    final ids =
        (assigns as List).map((a) => (a['id'] as num).toInt()).toList();
    if (ids.isEmpty) return 0;
    final statuses = await _taskStatusCodes();
    int? caliId;
    statuses.forEach((id, code) {
      if (code == 'CALI') caliId = id;
    });
    final subs = await _c
        .from('submissions')
        .select('id, task_status_id')
        .inFilter('assignment_id', ids);
    return (subs as List)
        .where((s) => (s['task_status_id'] as num?)?.toInt() != caliId)
        .length;
  }

  Future<List<AttendanceLine>> _teacherRoster(List<int> groupIds) async {
    if (groupIds.isEmpty) return const [];
    final rows = await _c
        .from('enrollments')
        .select('students(persons(first_name, last_name))')
        .eq('group_id', groupIds.first)
        .limit(5);
    return (rows as List)
        .map((r) => (r['students'] as Map?)?['persons'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map((p) => '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim())
        .where((n) => n.isNotEmpty)
        .map((n) => AttendanceLine(n, present: true))
        .toList();
  }

  // ------------------------------------------------------------------- Padre
  Future<ParentDashboardData> parentData(int parentId) async {
    final psRows = await _c
        .from('parent_students')
        .select('student_id, students(persons(first_name, last_name))')
        .eq('parent_id', parentId);
    final kids = (psRows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final p = (m['students'] as Map?)?['persons'] as Map<String, dynamic>?;
      final name =
          '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();
      return _ChildRef((m['student_id'] as num).toInt(),
          name.isEmpty ? 'Hijo' : name);
    }).toList();
    if (kids.isEmpty) return ParentDashboardData.empty();

    final children = [
      for (var i = 0; i < kids.length; i++)
        ChildBrief(kids[i].name, selected: i == 0),
    ];
    final childId = kids.first.id;
    final classIds = await _classIdsForStudent(childId);

    final results = await Future.wait([
      _classesInfo(classIds),
      _childRecentActivity(childId),
      _publishedAnnouncementsCount(),
      _attendancePct(studentId: childId),
      _eventsThisMonth(),
    ]);
    final classes = results[0] as List<_ClassInfo>;
    final activity = results[1] as List<ParentActivity>;
    final notices = results[2] as int;
    final attendance = results[3] as double;
    final events = results[4] as int;

    return ParentDashboardData(
      children: children,
      attendancePercent: attendance,
      monthEvents: events,
      newNotices: notices,
      subjects: classes
          .map((c) => ParentSubject(c.subject, c.teacher ?? 'Docente'))
          .toList(),
      recentActivity: activity,
    );
  }

  Future<List<ParentActivity>> _childRecentActivity(int studentId) async {
    final rows = await _c
        .from('grades')
        .select(
            'score, created_at, evaluations(title, max_score)')
        .eq('student_id', studentId)
        .not('score', 'is', null)
        .order('created_at', ascending: false)
        .limit(4);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final eval = m['evaluations'] as Map<String, dynamic>?;
      final max = (eval?['max_score'] as num?)?.toDouble() ?? 100;
      final raw = (m['score'] as num?)?.toDouble() ?? 0;
      final pct = max == 0 ? 0.0 : raw / max;
      return ParentActivity(
        tag: 'Nueva Nota',
        title: eval?['title'] as String? ?? 'Evaluación',
        score: '${(raw / max * 10).toStringAsFixed(1)}/10',
        timeAgo: _relativeWhen(DateTime.tryParse(m['created_at'] as String? ?? '')),
        progress: pct.clamp(0, 1).toDouble(),
      );
    }).toList();
  }

  // ------------------------------------------------------------ Administrador
  Future<AdminDashboardData> adminData() async {
    final results = await Future.wait([
      _count('students'),
      _count('teachers'),
      _institutionalAvg(),
      _attendancePct(),
      _announcements(),
      _adminTeachers(),
      _upcomingEventsCount(),
    ]);
    final announcements = results[4] as List<Announcement>;
    return AdminDashboardData(
      totalStudents: results[0] as int,
      activeTeachers: results[1] as int,
      institutionalAvg: results[2] as double,
      attendancePct: results[3] as double,
      announcements: announcements,
      teachers: results[5] as List<AdminTeacher>,
      upcomingEvents: results[6] as int,
      systemAlerts: announcements.length,
    );
  }

  /// Eventos del calendario en el mes actual (parent.monthEvents).
  Future<int> _eventsThisMonth() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    final rows = await _c
        .from('calendar_events')
        .select('id')
        .eq('institution_id', institutionId)
        .gte('start_at', start.toIso8601String())
        .lt('start_at', end.toIso8601String());
    return (rows as List).length;
  }

  /// Eventos futuros del calendario (admin.upcomingEvents).
  Future<int> _upcomingEventsCount() async {
    final rows = await _c
        .from('calendar_events')
        .select('id')
        .eq('institution_id', institutionId)
        .gte('start_at', DateTime.now().toIso8601String());
    return (rows as List).length;
  }

  Future<int> _count(String table) async {
    final rows =
        await _c.from(table).select('id').eq('institution_id', institutionId);
    return (rows as List).length;
  }

  Future<double> _institutionalAvg() async {
    final rows = await _c
        .from('student_weighted_averages')
        .select('weighted_pct')
        .eq('institution_id', institutionId);
    final vals = (rows as List)
        .map((r) => (r['weighted_pct'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    if (vals.isEmpty) return 0;
    return double.parse(
        (vals.reduce((a, b) => a + b) / vals.length / 10).toStringAsFixed(1));
  }

  Future<List<Announcement>> _announcements() async {
    final rows = await _c
        .from('announcements')
        .select('title, content')
        .eq('institution_id', institutionId)
        .eq('published', true)
        .order('published_at', ascending: false)
        .limit(5);
    return (rows as List)
        .map((r) => Announcement(
            r['title'] as String? ?? 'Anuncio', r['content'] as String? ?? ''))
        .toList();
  }

  Future<int> _publishedAnnouncementsCount() async {
    final rows = await _c
        .from('announcements')
        .select('id')
        .eq('institution_id', institutionId)
        .eq('published', true);
    return (rows as List).length;
  }

  Future<List<AdminTeacher>> _adminTeachers() async {
    final rows = await _c
        .from('teachers')
        .select('id, persons(first_name, last_name), classes(subjects(name))')
        .eq('institution_id', institutionId)
        .limit(6);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final p = m['persons'] as Map<String, dynamic>?;
      final name =
          '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();
      final classesList = (m['classes'] as List?) ?? const [];
      final subject = classesList.isEmpty
          ? 'Docente'
          : ((classesList.first as Map?)?['subjects'] as Map?)?['name']
                  as String? ??
              'Docente';
      return AdminTeacher(name.isEmpty ? 'Docente' : name, subject);
    }).toList();
  }

  /// % de asistencia REAL = presentes (código PRE, id 1) / total de registros.
  /// Si no hay registros aún, asume 100% (estudiante) / 94% (institución).
  Future<double> _attendancePct({int? studentId}) async {
    var query = _c
        .from('attendances')
        .select('attendance_status_id')
        .eq('institution_id', institutionId);
    if (studentId != null) query = query.eq('student_id', studentId);
    final rows = await query;
    final list = rows as List;
    if (list.isEmpty) return studentId != null ? 100.0 : 94.0;
    const presentStatusId = 1; // catalog_attendance_statuses code 'PRE'
    final present = list
        .where((r) => (r['attendance_status_id'] as num?)?.toInt() ==
            presentStatusId)
        .length;
    return double.parse((100.0 * present / list.length).toStringAsFixed(1));
  }

  Future<List<int>> _classIdsForStudent(int studentId) async {
    final enr = await _c
        .from('enrollments')
        .select('group_id')
        .eq('student_id', studentId)
        .eq('institution_id', institutionId);
    final groupIds = (enr as List)
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
    return (classes as List)
        .map((c) => (c['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
  }

  Future<List<_ClassInfo>> _classesInfo(List<int> classIds) async {
    final rows = await _c
        .from('classes')
        .select('id, subjects(name), teachers(persons(first_name, last_name))')
        .inFilter('id', classIds);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final person =
          (m['teachers'] as Map?)?['persons'] as Map<String, dynamic>?;
      final teacher = person == null
          ? null
          : '${person['first_name'] ?? ''} ${person['last_name'] ?? ''}'.trim();
      return _ClassInfo(
        id: (m['id'] as num).toInt(),
        subject: (m['subjects'] as Map?)?['name'] as String? ?? 'Materia',
        teacher: (teacher == null || teacher.isEmpty) ? null : teacher,
      );
    }).toList();
  }

  Future<List<ScheduleSlot>> _todaySchedule(List<int> classIds) async {
    final today = DateTime.now().weekday; // 1=Lun..7=Dom (coincide con weekday_id)
    final rows = await _c
        .from('schedules')
        .select(
            'start_time, end_time, weekday_id, classes(subjects(name)), classrooms(name)')
        .inFilter('class_id', classIds)
        .eq('weekday_id', today)
        .order('start_time');
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final subject = ((m['classes'] as Map?)?['subjects'] as Map?)?['name']
              as String? ??
          'Clase';
      return ScheduleSlot(
        startTime: _hhmm(m['start_time'] as String?),
        endTime: _hhmm(m['end_time'] as String?),
        subject: subject,
        room: (m['classrooms'] as Map?)?['name'] as String? ?? '',
        icon: iconForSubject(subject),
      );
    }).toList();
  }

  Future<List<TaskBrief>> _studentAssignments(
      List<int> classIds, int studentId) async {
    final rows = await _c
        .from('assignments')
        .select('id, title, due_at, classes(subjects(name))')
        .inFilter('class_id', classIds)
        .eq('published', true)
        .filter('deleted_at', 'is', null)
        .order('due_at')
        .limit(5);
    final assignmentIds =
        (rows as List).map((a) => (a['id'] as num).toInt()).toList();
    if (assignmentIds.isEmpty) return const [];

    final subs = await _c
        .from('submissions')
        .select('assignment_id, task_status_id')
        .inFilter('assignment_id', assignmentIds)
        .eq('student_id', studentId);
    final statuses = await _taskStatusCodes();
    final byAssignment = {
      for (final s in (subs as List))
        (s['assignment_id'] as num).toInt():
            statuses[(s['task_status_id'] as num?)?.toInt()],
    };

    return rows.map((m) {
      final id = (m['id'] as num).toInt();
      final subject =
          ((m['classes'] as Map?)?['subjects'] as Map?)?['name'] as String? ??
              'Materia';
      final code = byAssignment[id];
      final status = code == null
          ? TaskStatus.pending
          : (code == 'CALI'
              ? TaskStatus.reviewed
              : (code == 'ENTR'
                  ? TaskStatus.submitted
                  : TaskStatus.pending));
      return TaskBrief(
        title: m['title'] as String? ?? 'Tarea',
        subject: subject,
        status: status,
      );
    }).toList();
  }

  Future<List<GradeBrief>> _studentGrades(int studentId) async {
    final rows = await _c
        .from('grades')
        .select(
            'score, evaluations(title, max_score, classes(subjects(name)))')
        .eq('student_id', studentId)
        .not('score', 'is', null)
        .limit(5);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final eval = m['evaluations'] as Map<String, dynamic>?;
      final subject =
          ((eval?['classes'] as Map?)?['subjects'] as Map?)?['name'] as String? ??
              'Materia';
      final max = (eval?['max_score'] as num?)?.toDouble() ?? 100;
      final raw = (m['score'] as num?)?.toDouble() ?? 0;
      final score10 = max == 0 ? 0.0 : (raw / max * 10);
      final pct = max == 0 ? 0.0 : raw / max;
      return GradeBrief(
        subject: subject,
        activity: eval?['title'] as String? ?? 'Evaluación',
        score: double.parse(score10.toStringAsFixed(1)),
        status: pct >= 0.6 ? GradeStatus.passed : GradeStatus.lowPerformance,
      );
    }).toList();
  }

  Future<double> _weightedAverage(int studentId) async {
    final rows = await _c
        .from('student_weighted_averages')
        .select('weighted_pct')
        .eq('student_id', studentId);
    final vals = (rows as List)
        .map((r) => (r['weighted_pct'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    if (vals.isEmpty) return 0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  Future<List<String>> _classmates(int studentId) async {
    final groups = await _c
        .from('enrollments')
        .select('group_id')
        .eq('student_id', studentId);
    final groupIds = (groups as List)
        .map((e) => (e['group_id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    if (groupIds.isEmpty) return const [];
    final rows = await _c
        .from('enrollments')
        .select('students(persons(first_name, last_name))')
        .inFilter('group_id', groupIds)
        .neq('student_id', studentId);
    return (rows as List)
        .map((r) => (r['students'] as Map?)?['persons'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map((p) => '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  Map<int, String>? _statusCache;
  Future<Map<int, String>> _taskStatusCodes() async {
    final cached = _statusCache;
    if (cached != null) return cached;
    final rows = await _c.from('catalog_task_statuses').select('id, code');
    final map = {
      for (final r in (rows as List))
        (r['id'] as num).toInt(): r['code'] as String,
    };
    _statusCache = map;
    return map;
  }

  static String _hhmm(String? t) =>
      t == null ? '' : (t.length >= 5 ? t.substring(0, 5) : t);

  static const _months = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  static String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  static String _relativeWhen(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';
    return _shortDate(d);
  }
}

class _ClassInfo {
  _ClassInfo({required this.id, required this.subject, this.teacher});
  final int id;
  final String subject;
  final String? teacher;
}

class _ChildRef {
  _ChildRef(this.id, this.name);
  final int id;
  final String name;
}

/// Ícono por nombre de materia (best-effort para la UI).
IconData iconForSubject(String name) {
  final n = name.toLowerCase();
  if (n.contains('matem')) return Icons.calculate_rounded;
  if (n.contains('histor')) return Icons.account_balance_outlined;
  if (n.contains('fís') || n.contains('fis') || n.contains('cuánt')) {
    return Icons.science_outlined;
  }
  if (n.contains('biolog') || n.contains('celul')) return Icons.biotech_outlined;
  if (n.contains('litera') || n.contains('lengua')) return Icons.menu_book_rounded;
  if (n.contains('geograf')) return Icons.public_rounded;
  if (n.contains('geometr')) return Icons.architecture_rounded;
  return Icons.menu_book_rounded;
}
