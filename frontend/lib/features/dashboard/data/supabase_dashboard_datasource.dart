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
  Future<StudentDashboardData> studentData(
    int studentId, {
    bool showGrades = true,
  }) async {
    final classIds = await _classIdsForStudent(studentId);
    if (classIds.isEmpty) return StudentDashboardData.empty();

    final results = await Future.wait([
      _classesInfo(classIds),
      _todaySchedule(classIds),
      _studentAssignments(classIds, studentId),
      showGrades ? _studentGrades(studentId) : Future.value(<GradeBrief>[]),
      showGrades ? _weightedAverage(studentId) : Future.value(0.0),
      _classmates(studentId),
      _studentGradeGroup(studentId),
      _attendancePct(studentId: studentId),
      _c.rpc('assignment_counters',params:{'p_student_id':studentId}).then<dynamic>((value)=>value),
    ]);

    final classes = results[0] as List<_ClassInfo>;
    final schedule = results[1] as List<ScheduleSlot>;
    final tasks = results[2] as List<TaskBrief>;
    final grades = results[3] as List<GradeBrief>;
    final avg = results[4] as double;
    final classmates = results[5] as List<String>;
    final gradeGroup = results[6] as String;
    final attendancePct = results[7] as double;

    final subjects = classes
        .map(
          (c) => SubjectProgress(
            name: c.subject,
            teacher: c.teacher ?? 'Docente',
            progress: (avg / 100).clamp(0, 1).toDouble(),
            icon: iconForSubject(c.subject),
          ),
        )
        .toList();

    final pending = ((results[8] as Map)['pending'] as num).toInt();

    return StudentDashboardData(
      pendingTasks: pending,
      todaySchedule: schedule,
      subjects: subjects,
      tasks: tasks,
      grades: grades,
      averageScore: double.parse((avg / 10).toStringAsFixed(1)),
      classmates: classmates.take(4).toList(),
      classmatesExtra: classmates.length > 4 ? classmates.length - 4 : 0,
      attendanceRate: attendancePct / 100,
      gradeGroup: gradeGroup,
    );
  }

  // ------------------------------------------------------------------ Docente
  Future<TeacherDashboardData> teacherData(int teacherId) async {
    final workspace = Map<String, dynamic>.from(
      await _c.rpc('teacher_dashboard_classes') as Map,
    );
    final classes = (workspace['classes'] as List)
        .map(
          (c) => <String, dynamic>{
            'id': c['classId'],
            'group_id': c['groupId'],
            'subjects': {'name': c['subjectName']},
            'groups': {'name': c['groupName']},
            'isOwner': c['isOwner'],
            'permissions': c['permissions'],
          },
        )
        .toList();
    if (classes.isEmpty) return TeacherDashboardData.empty();

    final classIds = classes.map((c) => (c['id'] as num).toInt()).toList();
    final groupIds = classes
        .map((c) => (c['group_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();

    final results = await Future.wait([
      _teacherAssignments(classIds),
      _teacherRecentGrades(classIds),
      _todaySchedule(classIds),
      _teacherPendingGrading(classIds),
      _teacherRoster(groupIds),
    ]);

    final myClasses = classes
        .map(
          (c) => TeacherClass(
            classId: c['id'] as int,
            isOwner: c['isOwner'] == true,
            permissions: Set<String>.from(c['permissions'] as List),
            name: (c['subjects'] as Map?)?['name'] as String? ?? 'Clase',
            room: (c['groups'] as Map?)?['name'] as String? ?? '',
            icon: iconForSubject(
              (c['subjects'] as Map?)?['name'] as String? ?? '',
            ),
          ),
        )
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
    List<int> classIds,
  ) async {
    final rows = await _c
        .from('assignments')
        .select('id, title, due_at, class_id, classes(groups(name))')
        .inFilter('class_id', classIds)
        .filter('deleted_at', 'is', null)
        .order('due_at', ascending: true)
        .limit(6);
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return const [];

    final ids = list.map((a) => (a['id'] as num).toInt()).toList();
    final counts = await _c
        .rpc('dashboard_assignment_counts', params: {'p_assignment_ids': ids});
    final countsByAssignment = <int, Map<String, dynamic>>{
      for (final row in (counts as List).cast<Map<String, dynamic>>())
        (row['assignment_id'] as num).toInt(): row,
    };

    final now = DateTime.now();
    return list.map((a) {
      final group =
          ((a['classes'] as Map?)?['groups'] as Map?)?['name'] as String? ??
              'Grupo';
      final due = DateTime.tryParse(a['due_at'] as String? ?? '');
      final aid = (a['id'] as num).toInt();
      final delivered =
          (countsByAssignment[aid]?['delivered'] as num?)?.toInt() ?? 0;
      final total = (countsByAssignment[aid]?['total'] as num?)?.toInt() ?? 0;
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
    if (classIds.isEmpty) return const [];
    final rows = await _c
        .from('grades')
        .select(
          'score, evaluation_id, created_at, students(persons(first_name, last_name)), evaluations!inner(max_score,title,class_id)',
        )
        .eq('institution_id',institutionId)
        .inFilter('evaluations.class_id',classIds)
        .not('score', 'is', null)
        .order('created_at', ascending: false)
        .order('id',ascending:false)
        .limit(5);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final person =
          (m['students'] as Map?)?['persons'] as Map<String, dynamic>?;
      final name =
          '${person?['first_name'] ?? ''} ${person?['last_name'] ?? ''}'.trim();
      final max =
          ((m['evaluations'] as Map?)?['max_score'] as num?)?.toDouble() ?? 100;
      final raw = (m['score'] as num?)?.toDouble() ?? 0;
      final title = (m['evaluations'] as Map?)?['title'] as String? ?? 'Evaluación';
      return RecentGrade(
        name.isEmpty ? 'Estudiante' : name,
        'Tema: $title',
        double.parse((max == 0 ? 0.0 : raw / max * 10).toStringAsFixed(1)),
        _relativeWhen(DateTime.tryParse(m['created_at'] as String? ?? '')),
      );
    }).toList();
  }

  Future<int> _teacherPendingGrading(List<int> classIds) async {
    return (await _c.rpc('dashboard_pending_grading',
            params: {'p_class_ids': classIds},) as num)
        .toInt();
  }

  Future<List<AttendanceLine>> _teacherRoster(List<int> groupIds) async {
    if (groupIds.isEmpty) return const [];
    final rows = await _c
        .from('enrollments')
        .select('students!inner(persons(first_name, last_name),active),academic_years!inner(is_current),catalog_enrollment_statuses!inner(code)')
        .eq('institution_id',institutionId)
        .eq('students.active',true)
        .eq('academic_years.is_current',true)
        .eq('catalog_enrollment_statuses.code','ACT')
        .eq('group_id', groupIds.first)
        .order('student_id', ascending: true)
        .limit(5);
    return (rows as List)
        .map(
          (r) => (r['students'] as Map?)?['persons'] as Map<String, dynamic>?,
        )
        .whereType<Map<String, dynamic>>()
        .map((p) => '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim())
        .where((n) => n.isNotEmpty)
        .map((n) => AttendanceLine(n, present: true))
        .toList();
  }

  // ------------------------------------------------------------------- Padre
  Future<ParentDashboardData> parentData(
    int parentId, {
    bool showGrades = true,
  }) async {
    final psRows = await _c
        .from('parent_students')
        .select('student_id, students(persons(first_name, last_name))')
        .eq('parent_id', parentId);
    final kids = (psRows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final p = (m['students'] as Map?)?['persons'] as Map<String, dynamic>?;
      final name = '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();
      return _ChildRef(
        (m['student_id'] as num).toInt(),
        name.isEmpty ? 'Hijo' : name,
      );
    }).toList();
    if (kids.isEmpty) return ParentDashboardData.empty();

    final children = [
      for (var i = 0; i < kids.length; i++)
        ChildBrief(kids[i].name, id: kids[i].id, selected: i == 0),
    ];
    final childId = kids.first.id;
    final classIds = await _classIdsForStudent(childId);

    final results = await Future.wait([
      _classesInfo(classIds),
      showGrades
          ? _childRecentActivity(childId)
          : Future.value(<ParentActivity>[]),
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
          'score, created_at, evaluations(title, max_score)',
        )
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
        timeAgo:
            _relativeWhen(DateTime.tryParse(m['created_at'] as String? ?? '')),
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
    return await _c
        .from('calendar_events')
        .count(CountOption.exact)
        .eq('institution_id', institutionId)
        .gte('start_at', start.toIso8601String())
        .lt('start_at', end.toIso8601String());
  }

  /// Eventos futuros del calendario (admin.upcomingEvents).
  Future<int> _upcomingEventsCount() async {
    return await _c
        .from('calendar_events')
        .count(CountOption.exact)
        .eq('institution_id', institutionId)
        .gte('start_at', DateTime.now().toIso8601String());
  }

  Future<int> _count(String table) async {
    return await _c
        .from(table)
        .count(CountOption.exact)
        .eq('institution_id', institutionId)
        .eq('active', true);
  }

  Future<double> _institutionalAvg() async {
    return (await _c.rpc('dashboard_institutional_average') as num).toDouble();
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
        .map(
          (r) => Announcement(
            r['title'] as String? ?? 'Anuncio',
            r['content'] as String? ?? '',
          ),
        )
        .toList();
  }

  Future<int> _publishedAnnouncementsCount() async {
    return await _c
        .from('announcements')
        .count(CountOption.exact)
        .eq('institution_id', institutionId)
        .eq('published', true);
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
      final name = '${p?['first_name'] ?? ''} ${p?['last_name'] ?? ''}'.trim();
      final classesList = (m['classes'] as List?) ?? const [];
      final subject = classesList.isEmpty
          ? 'Docente'
          : ((classesList.first as Map?)?['subjects'] as Map?)?['name']
                  as String? ??
              'Docente';
      return AdminTeacher(name.isEmpty ? 'Docente' : name, subject);
    }).toList();
  }

  /// Current academic year, using the PRE catalog code rather than a fixed ID.
  Future<double> _attendancePct({int? studentId}) async {
    return (await _c.rpc('dashboard_attendance_pct',
            params: {'p_student_id': studentId},) as num)
        .toDouble();
  }

  Future<List<int>> _classIdsForStudent(int studentId) async {
    final enr = await _c
        .from('enrollments')
        .select(
            'group_id, academic_years!inner(is_current), catalog_enrollment_statuses!inner(code)',)
        .eq('student_id', studentId)
        .eq('institution_id', institutionId)
        .eq('academic_years.is_current', true)
        .eq('catalog_enrollment_statuses.code', 'ACT');
    final groupIds = (enr as List)
        .map((e) => (e['group_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();
    if (groupIds.isEmpty) return const [];
    final classes = await _c
        .from('classes')
        .select('id,academic_years!inner(is_current)')
        .inFilter('group_id', groupIds)
        .eq('institution_id', institutionId)
        .eq('academic_years.is_current',true)
        .eq('active',true);
    return (classes as List)
        .map((c) => (c['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
  }

  Future<List<_ClassInfo>> _classesInfo(List<int> classIds) async {
    final rows = await _c
        .from('classes')
        .select('id, subjects(name), teachers(persons(first_name, last_name))')
        .inFilter('id', classIds)
        .eq('institution_id', institutionId);
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
    final today =
        DateTime.now().weekday; // 1=Lun..7=Dom (coincide con weekday_id)
    final rows = await _c
        .from('schedules')
        .select(
          'start_time, end_time, weekday_id, classes(subjects(name), teachers(persons(first_name, last_name))), classrooms(name)',
        )
        .inFilter('class_id', classIds)
        .eq('institution_id', institutionId)
        .eq('weekday_id', today)
        .order('start_time', ascending: true);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final subject =
          ((m['classes'] as Map?)?['subjects'] as Map?)?['name'] as String? ??
              'Clase';
      final person =
          ((m['classes'] as Map?)?['teachers'] as Map?)?['persons'] as Map?;
      final teacher =
          '${person?['first_name'] ?? ''} ${person?['last_name'] ?? ''}'.trim();
      return ScheduleSlot(
        startTime: _hhmm(m['start_time'] as String?),
        endTime: _hhmm(m['end_time'] as String?),
        subject: subject,
        room: (m['classrooms'] as Map?)?['name'] as String? ?? '',
        teacher: teacher.isEmpty ? null : teacher,
        icon: iconForSubject(subject),
      );
    }).toList();
  }

  Future<List<TaskBrief>> _studentAssignments(
    List<int> classIds,
    int studentId,
  ) async {
    final rows = await _c
        .from('assignments')
        .select('id, title, due_at, classes(subjects(name))')
        .inFilter('class_id', classIds)
        .eq('institution_id', institutionId)
        .eq('published', true)
        .filter('deleted_at', 'is', null)
        .order('due_at', ascending: true)
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
              : (code == 'ENTR' ? TaskStatus.submitted : TaskStatus.pending));
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
          'score, evaluations(title, max_score, classes(subjects(name)))',
        )
        .eq('student_id', studentId)
        .eq('institution_id', institutionId)
        .not('score', 'is', null)
        .limit(5);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final eval = m['evaluations'] as Map<String, dynamic>?;
      final subject = ((eval?['classes'] as Map?)?['subjects'] as Map?)?['name']
              as String? ??
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
    return (await _c.rpc('dashboard_student_average',
            params: {'p_student_id': studentId},) as num)
        .toDouble();
  }

  Future<List<String>> _classmates(int studentId) async {
    final groups = await _c
        .from('enrollments')
        .select(
            'group_id, academic_years!inner(is_current), catalog_enrollment_statuses!inner(code)',)
        .eq('student_id', studentId)
        .eq('institution_id', institutionId)
        .eq('academic_years.is_current', true)
        .eq('catalog_enrollment_statuses.code', 'ACT');
    final groupIds = (groups as List)
        .map((e) => (e['group_id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    if (groupIds.isEmpty) return const [];
    final rows = await _c
        .from('enrollments')
        .select(
            'students(persons(first_name, last_name)), academic_years!inner(is_current), catalog_enrollment_statuses!inner(code)',)
        .inFilter('group_id', groupIds)
        .eq('institution_id', institutionId)
        .eq('academic_years.is_current', true)
        .eq('catalog_enrollment_statuses.code', 'ACT')
        .neq('student_id', studentId);
    return (rows as List)
        .map(
          (r) => (r['students'] as Map?)?['persons'] as Map<String, dynamic>?,
        )
        .whereType<Map<String, dynamic>>()
        .map((p) => '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  Future<String> _studentGradeGroup(int studentId) async {
    final rows = await _c
        .from('enrollments')
        .select(
            'groups(name), academic_years!inner(is_current), catalog_enrollment_statuses!inner(code)',)
        .eq('student_id', studentId)
        .eq('institution_id', institutionId)
        .eq('academic_years.is_current', true)
        .eq('catalog_enrollment_statuses.code', 'ACT')
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return '';
    final group = (list.first as Map<String, dynamic>)['groups'] as Map?;
    return group?['name'] as String? ?? '';
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
    'Ene',
    'Feb',
    'Mar',
    'Abr',
    'May',
    'Jun',
    'Jul',
    'Ago',
    'Sep',
    'Oct',
    'Nov',
    'Dic',
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
  if (n.contains('histor')) return Icons.account_balance_rounded;
  if (n.contains('fís') || n.contains('fis') || n.contains('cuánt')) {
    return Icons.science_rounded;
  }
  if (n.contains('biolog') || n.contains('celul')) return Icons.biotech_rounded;
  if (n.contains('litera') || n.contains('lengua')) {
    return Icons.menu_book_rounded;
  }
  if (n.contains('geograf')) return Icons.public_rounded;
  if (n.contains('geometr')) return Icons.architecture_rounded;
  return Icons.menu_book_rounded;
}
