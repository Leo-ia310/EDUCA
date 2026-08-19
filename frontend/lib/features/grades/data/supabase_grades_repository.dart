import 'package:flutter/painting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/backend_api_client.dart';
import '../domain/entities.dart';
import '../domain/grades_calculator.dart';
import '../domain/grades_repository.dart';

/// Implementación real contra Supabase.
///
/// Tablas usadas (ver `supabase/migrations/0001_init_core.sql` y
/// `0002_init_academic_extras.sql`): `grading_scales`, `grading_scale_ranges`,
/// `academic_years`, `academic_periods`, `evaluations`, `grades`,
/// `institution_settings` (para la escala por defecto — la tabla no tiene su
/// propia columna `is_default`).
///
/// La lógica de ponderación vive en [GradesCalculator] (compartida con el
/// repo mock) — este repositorio solo arma los datos crudos desde la BD.
class SupabaseGradesRepository implements GradesRepository {
  SupabaseGradesRepository({
    required SupabaseClient client,
    required BackendApiClient api,
    required this.institutionId,
  })  : _c = client,
        _api = api;

  final SupabaseClient _c;
  final BackendApiClient _api;
  final int institutionId;
  final _calc = const GradesCalculator();

  static const _defaultScaleKey = 'default_grading_scale_id';
  static const _scaleSelect =
      'id, name, scale_type, min_value, max_value, pass_value, decimals, '
      'active, grading_scale_ranges(label, range_min, range_max, description, passed, color)';

  // ---------- Escalas ----------
  @override
  Future<List<GradingScale>> scales() async {
    final rows = await _c
        .from('grading_scales')
        .select(_scaleSelect)
        .eq('institution_id', institutionId)
        .eq('active', true);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_scaleFromRow)
        .toList();
  }

  @override
  Future<GradingScale> defaultScale() async {
    final all = await scales();
    if (all.isEmpty) {
      throw StateError('No hay escalas de calificación configuradas');
    }
    final setting = await _c
        .from('institution_settings')
        .select('value')
        .eq('institution_id', institutionId)
        .eq('key', _defaultScaleKey)
        .maybeSingle();
    final defaultId = setting?['value'] as String?;
    return all.firstWhere((s) => s.id == defaultId, orElse: () => all.first);
  }

  @override
  Future<GradingScale> upsertScale(GradingScale scale) async {
    final response = await _api.call('grades.upsertScale', {
      'id': int.tryParse(scale.id),
      'name': scale.name,
      'type': scale.type.name,
      'minValue': scale.minValue,
      'maxValue': scale.maxValue,
      'passValue': scale.passValue,
      'decimals': scale.decimals,
      'ranges': scale.ranges
          .map(
            (r) => {
              'label': r.label,
              'rangeMin': r.rangeMin,
              'rangeMax': r.rangeMax,
              'description': r.description,
              'passed': r.passed,
              'color': r.color == null ? null : _colorToHex(r.color!),
            },
          )
          .toList(),
    });
    final data = Map<String, dynamic>.from(response as Map);
    return _scaleFromRow(Map<String, dynamic>.from(data['scale'] as Map));
  }

  @override
  Future<void> setDefaultScale(String id) async {
    await _api.call('grades.setDefaultScale', {'id': id});
  }

  GradingScale _scaleFromRow(Map<String, dynamic> row) {
    final ranges = (row['grading_scale_ranges'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (r) => ScaleRange(
            label: r['label'] as String? ?? '',
            rangeMin: (r['range_min'] as num?)?.toDouble() ?? 0,
            rangeMax: (r['range_max'] as num?)?.toDouble() ?? 0,
            passed: r['passed'] as bool? ?? true,
            description: r['description'] as String?,
            color: _parseColor(r['color'] as String?),
          ),
        )
        .toList();
    return GradingScale(
      id: row['id'].toString(),
      name: row['name'] as String? ?? '',
      type: _scaleTypeFrom(row['scale_type'] as String?),
      minValue: (row['min_value'] as num?)?.toDouble() ?? 0,
      maxValue: (row['max_value'] as num?)?.toDouble() ?? 100,
      passValue: (row['pass_value'] as num?)?.toDouble() ?? 60,
      decimals: (row['decimals'] as num?)?.toInt() ?? 0,
      ranges: ranges,
    );
  }

  ScaleType _scaleTypeFrom(String? v) {
    for (final t in ScaleType.values) {
      if (t.name == v) return t;
    }
    return ScaleType.numeric;
  }

  Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  String _colorToHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  // ---------- Periodos ----------
  Future<int?> _currentAcademicYearId() async {
    final row = await _c
        .from('academic_years')
        .select('id')
        .eq('institution_id', institutionId)
        .eq('is_current', true)
        .maybeSingle();
    return row == null ? null : (row['id'] as num).toInt();
  }

  @override
  Future<List<AcademicPeriod>> periods() async {
    final yearId = await _currentAcademicYearId();
    if (yearId == null) return const [];
    final rows = await _c
        .from('academic_periods')
        .select('id, name, start_date, end_date, weight, closed')
        .eq('institution_id', institutionId)
        .eq('academic_year_id', yearId)
        .order('display_order');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(
          (r) => AcademicPeriod(
            id: r['id'].toString(),
            name: r['name'] as String? ?? '',
            startDate: DateTime.tryParse(r['start_date'] as String? ?? '') ??
                DateTime.now(),
            endDate: DateTime.tryParse(r['end_date'] as String? ?? '') ??
                DateTime.now(),
            weight: (r['weight'] as num?)?.toDouble() ?? 0,
            closed: r['closed'] as bool? ?? false,
          ),
        )
        .toList();
  }

  // ---------- Evaluaciones y notas ----------
  Future<List<int>> _classIdsForStudent(int studentId) async {
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
    return (classes as List)
        .map((c) => (c['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
  }

  @override
  Future<List<Evaluation>> evaluationsFor({
    required int studentId,
    String? periodId,
    int? classId,
  }) async {
    final classIds =
        classId != null ? [classId] : await _classIdsForStudent(studentId);
    if (classIds.isEmpty) return const [];
    var query = _c
        .from('evaluations')
        .select(
          'id, class_id, title, date, max_score, weight, academic_period_id, '
          'classes(subjects(name)), catalog_evaluation_types(code)',
        )
        .inFilter('class_id', classIds)
        .eq('institution_id', institutionId)
        .eq('published', true);
    if (periodId != null) query = query.eq('academic_period_id', periodId);
    final rows = await query.order('date');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_evalFromRow)
        .toList();
  }

  Evaluation _evalFromRow(Map<String, dynamic> row) {
    final subject = (row['classes'] as Map?)?['subjects'] as Map?;
    final kindCode =
        (row['catalog_evaluation_types'] as Map?)?['code'] as String?;
    return Evaluation(
      id: row['id'].toString(),
      classId: (row['class_id'] as num).toInt(),
      subjectName: subject?['name'] as String? ?? 'Materia',
      periodId: row['academic_period_id'].toString(),
      title: row['title'] as String? ?? '',
      date: DateTime.tryParse(row['date'] as String? ?? '') ?? DateTime.now(),
      maxScore: (row['max_score'] as num?)?.toDouble() ?? 100,
      weight: (row['weight'] as num?)?.toDouble() ?? 1,
      kind: kindCode?.toLowerCase() ?? 'homework',
    );
  }

  @override
  Future<List<GradeEntry>> gradesFor({
    required int studentId,
    String? periodId,
  }) async {
    final rows = await _c
        .from('grades')
        .select(
            'evaluation_id, student_id, score, notes, evaluations!inner(academic_period_id)')
        .eq('student_id', studentId)
        .eq('institution_id', institutionId);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .where((r) {
          if (periodId == null) return true;
          final evalPeriod =
              (r['evaluations'] as Map?)?['academic_period_id']?.toString();
          return evalPeriod == periodId;
        })
        .map(
          (r) => GradeEntry(
            evaluationId: r['evaluation_id'].toString(),
            studentId: (r['student_id'] as num).toInt(),
            rawScore: (r['score'] as num?)?.toDouble() ?? 0,
            notes: r['notes'] as String?,
          ),
        )
        .toList();
  }

  Future<List<({int classId, String name, String teacher})>>
      _subjectsForStudent(int studentId) async {
    final classIds = await _classIdsForStudent(studentId);
    if (classIds.isEmpty) return const [];
    final rows = await _c
        .from('classes')
        .select('id, subjects(name), teachers(persons(first_name, last_name))')
        .inFilter('id', classIds);
    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      final subjectName =
          (r['subjects'] as Map?)?['name'] as String? ?? 'Materia';
      final person = (r['teachers'] as Map?)?['persons'] as Map?;
      final teacherName =
          '${person?['first_name'] ?? ''} ${person?['last_name'] ?? ''}'.trim();
      return (
        classId: (r['id'] as num).toInt(),
        name: subjectName,
        teacher: teacherName.isEmpty ? 'Docente' : teacherName,
      );
    }).toList();
  }

  @override
  Future<List<SubjectPerformance>> performanceForStudent({
    required int studentId,
    GradingScale? scale,
  }) async {
    final s = scale ?? await defaultScale();
    final periodsList = await periods();
    final subjects = await _subjectsForStudent(studentId);
    final myGrades = await gradesFor(studentId: studentId);
    final gradesByEval = {for (final g in myGrades) g.evaluationId: g};

    final result = <SubjectPerformance>[];
    for (final subj in subjects) {
      final periodGrades = <String, PeriodGrade>{};
      for (final p in periodsList) {
        final evals = await evaluationsFor(
          studentId: studentId,
          periodId: p.id,
          classId: subj.classId,
        );
        final matchingGrades = evals
            .where((e) => gradesByEval.containsKey(e.id))
            .map((e) => gradesByEval[e.id]!)
            .toList();
        periodGrades[p.id] = _calc.computePeriodGrade(
          studentId: studentId,
          subjectName: subj.name,
          periodId: p.id,
          evaluations: evals,
          grades: matchingGrades,
          scale: s,
        );
      }
      result.add(
        _calc.computeSubjectPerformance(
          subjectName: subj.name,
          teacherName: subj.teacher,
          periodGrades: periodGrades,
          periods: periodsList,
          scale: s,
        ),
      );
    }
    return result;
  }

  @override
  Future<ReportCard> reportCardForStudent({
    required int studentId,
    String? periodId,
    GradingScale? scale,
  }) async {
    final s = scale ?? await defaultScale();
    final periodsList = await periods();
    final targetPeriod = periodId == null
        ? null
        : periodsList.firstWhere((p) => p.id == periodId);
    final performances =
        await performanceForStudent(studentId: studentId, scale: s);

    final lines = <ReportCardLine>[];
    for (final perf in performances) {
      final score = targetPeriod == null
          ? perf.finalScore
          : (perf.periodScores[targetPeriod.id] ?? 0);
      lines.add(
        ReportCardLine(
          subjectName: perf.subjectName,
          teacherName: perf.teacherName,
          finalScore: score,
          qualitativeLabel: s.labelFor(score),
          passed: s.isPassing(score),
        ),
      );
    }
    final overall = targetPeriod == null
        ? _calc.overallAverage(performances)
        : _averageOfLines(lines);

    final info = await _studentInfo(studentId);
    final attendancePct = await _attendancePct(studentId);
    final totalPeers = await _peerCount(studentId);

    return ReportCard(
      studentId: studentId,
      studentName: info.name,
      institutionName: info.institutionName,
      gradeLevel: info.gradeLevel,
      periodName: targetPeriod?.name ?? 'Anual',
      periodStart:
          targetPeriod?.startDate ?? DateTime(DateTime.now().year, 1, 1),
      periodEnd: targetPeriod?.endDate ?? DateTime(DateTime.now().year, 12, 31),
      lines: lines,
      overallAverage: overall,
      overallLabel: s.labelFor(overall),
      attendancePct: attendancePct,
      // El ranking real entre compañeros de grupo requeriría un agregado
      // `period_grades` (aún no poblado por ningún proceso) o una función
      // RPC en Postgres — calcularlo aquí dispararía una consulta por
      // compañero de clase. Se deja en 1 como placeholder honesto hasta que
      // exista esa agregación.
      rank: 1,
      totalPeers: totalPeers,
    );
  }

  Future<({String name, String institutionName, String gradeLevel})>
      _studentInfo(int studentId) async {
    final row = await _c
        .from('students')
        .select(
          'persons(first_name, last_name), institutions(name), '
          'enrollments(group_id, groups(name, grade_levels(name), sections(name)))',
        )
        .eq('id', studentId)
        .single();
    final person = row['persons'] as Map<String, dynamic>?;
    final name =
        '${person?['first_name'] ?? ''} ${person?['last_name'] ?? ''}'.trim();
    final institutionName =
        (row['institutions'] as Map?)?['name'] as String? ?? 'Colegio';
    final enrollments =
        (row['enrollments'] as List? ?? const []).cast<Map<String, dynamic>>();
    final group = enrollments.isEmpty
        ? null
        : enrollments.first['groups'] as Map<String, dynamic>?;
    final gradeLevel = group == null
        ? '—'
        : '${(group['grade_levels'] as Map?)?['name'] ?? ''} '
                '${(group['sections'] as Map?)?['name'] ?? ''}'
            .trim();
    return (
      name: name.isEmpty ? 'Estudiante' : name,
      institutionName: institutionName,
      gradeLevel: gradeLevel.isEmpty ? '—' : gradeLevel,
    );
  }

  Future<double> _attendancePct(int studentId) async {
    final rows = await _c
        .from('attendances')
        .select('catalog_attendance_statuses(counts_as_absent)')
        .eq('student_id', studentId);
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return 100;
    final absentCount = list
        .where(
          (r) =>
              (r['catalog_attendance_statuses'] as Map?)?['counts_as_absent'] ==
              true,
        )
        .length;
    final presentPct = ((list.length - absentCount) / list.length) * 100;
    return double.parse(presentPct.toStringAsFixed(1));
  }

  Future<int> _peerCount(int studentId) async {
    final mine = await _c
        .from('enrollments')
        .select('group_id')
        .eq('student_id', studentId)
        .eq('institution_id', institutionId)
        .maybeSingle();
    final groupId = mine?['group_id'];
    if (groupId == null) return 1;
    final peers = await _c
        .from('enrollments')
        .select('id')
        .eq('group_id', groupId as Object);
    return (peers as List).length;
  }

  double _averageOfLines(List<ReportCardLine> lines) {
    final valid = lines.where((l) => l.finalScore > 0).toList();
    if (valid.isEmpty) return 0;
    final sum = valid.fold<double>(0, (a, l) => a + l.finalScore);
    return double.parse((sum / valid.length).toStringAsFixed(2));
  }

  // ---------- Gradebook ----------
  @override
  Future<GradebookMatrix> gradebook({
    required int classId,
    required String periodId,
  }) async {
    final evalRows = await _c
        .from('evaluations')
        .select(
          'id, class_id, title, date, max_score, weight, academic_period_id, '
          'classes(subjects(name)), catalog_evaluation_types(code)',
        )
        .eq('class_id', classId)
        .eq('academic_period_id', periodId)
        .eq('institution_id', institutionId)
        .order('date');
    final evaluations = (evalRows as List)
        .cast<Map<String, dynamic>>()
        .map(_evalFromRow)
        .toList();

    final classRow =
        await _c.from('classes').select('group_id').eq('id', classId).single();
    final groupId = classRow['group_id'];

    final enrollments = await _c
        .from('enrollments')
        .select('student_id, students(id, persons(first_name, last_name))')
        .eq('group_id', groupId as Object)
        .eq('institution_id', institutionId);
    final students =
        (enrollments as List).cast<Map<String, dynamic>>().map((e) {
      final person = (e['students'] as Map?)?['persons'] as Map?;
      final name =
          '${person?['first_name'] ?? ''} ${person?['last_name'] ?? ''}'.trim();
      return (
        studentId: (e['student_id'] as num).toInt(),
        name: name.isEmpty ? 'Estudiante' : name,
      );
    }).toList();

    final evaluationIds = evaluations.map((e) => e.id).toList();
    final gradeRows = evaluationIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _c
                .from('grades')
                .select('evaluation_id, student_id, score')
                .inFilter('evaluation_id', evaluationIds)
                .eq('institution_id', institutionId) as List)
            .cast<Map<String, dynamic>>();

    final grades = <int, Map<String, double?>>{
      for (final st in students)
        st.studentId: {for (final e in evaluations) e.id: null},
    };
    for (final g in gradeRows) {
      final sid = (g['student_id'] as num).toInt();
      final eid = g['evaluation_id'].toString();
      grades[sid]?[eid] = (g['score'] as num?)?.toDouble();
    }

    return GradebookMatrix(
        evaluations: evaluations, students: students, grades: grades);
  }

  @override
  Future<void> setGrade({
    required String evaluationId,
    required int studentId,
    required double rawScore,
    String? notes,
  }) async {
    await _api.call('grades.setGrade', {
      'evaluationId': evaluationId,
      'studentId': studentId,
      'rawScore': rawScore,
      'notes': notes,
    });
  }
}
