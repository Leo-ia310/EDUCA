import 'package:flutter/painting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/read_all.dart';
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
    final scale = await findDefaultScale();
    if (scale == null) {
      throw StateError('No hay escalas de calificación configuradas');
    }
    return scale;
  }

  @override
  Future<GradingScale?> findDefaultScale() async {
    final response = await _api.get('/grades/scales/default');
    final data = Map<String, dynamic>.from(response as Map);
    final row = data['scale'];
    return row == null
        ? null
        : _scaleFromRow(Map<String, dynamic>.from(row as Map));
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
  Future<List<Map<String, dynamic>>> _classesForStudent(int studentId) async {
    final enrollment = await _c
        .from('enrollments')
        .select(
            'group_id, academic_year_id, academic_years!inner(is_current), catalog_enrollment_statuses!inner(code)',)
        .eq('student_id', studentId)
        .eq('institution_id', institutionId)
        .eq('academic_years.is_current', true)
        .eq('catalog_enrollment_statuses.code', 'ACT')
        .maybeSingle();
    if (enrollment == null) return [];
    return readAllPages<Map<String, dynamic>>((from, to) async => await _c
        .from('classes')
        .select('id, subjects(name), teachers(persons(first_name, last_name))')
        .eq('group_id', enrollment['group_id'] as Object)
        .eq('academic_year_id', enrollment['academic_year_id'] as Object)
        .eq('institution_id', institutionId)
        .eq('active', true)
        .order('id')
        .range(from, to),);
  }

  static const _evaluationSelect =
      'id, class_id, title, date, max_score, weight, academic_period_id, '
      'classes(subjects(name)), catalog_evaluation_types(code), academic_periods!inner(academic_years!inner(is_current))';

  Future<List<Evaluation>> _evaluationsOfClasses(List<int> classIds,
      {String? periodId,}) async {
    final result = <Evaluation>[];
    for (var i = 0; i < classIds.length; i += 150) {
      final rows = await readAllPages<Map<String, dynamic>>((from, to) async {
        var query = _c
            .from('evaluations')
            .select(_evaluationSelect)
            .inFilter('class_id',
                classIds.sublist(i, (i + 150).clamp(0, classIds.length)),)
            .eq('institution_id', institutionId)
            .eq('academic_periods.academic_years.is_current', true)
            .eq('published', true);
        if (periodId != null) query = query.eq('academic_period_id', periodId);
        return await query.order('date').order('id').range(from, to);
      });
      result.addAll(rows.map(_evalFromRow));
    }
    return result;
  }

  @override
  Future<List<Evaluation>> evaluationsFor(
      {required int studentId, String? periodId, int? classId,}) async {
    final ids = classId == null
        ? (await _classesForStudent(studentId))
            .map((r) => (r['id'] as num).toInt())
            .toList()
        : [classId];
    return _evaluationsOfClasses(ids, periodId: periodId);
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
    final rows = await readAllPages<Map<String, dynamic>>((from, to) async {
      var query = _c
          .from('grades')
          .select(
              'evaluation_id, student_id, score, notes, evaluations!inner(academic_period_id, academic_periods!inner(academic_years!inner(is_current)))',)
          .eq('student_id', studentId)
          .eq('institution_id', institutionId)
          .eq('evaluations.academic_periods.academic_years.is_current', true)
          .not('score', 'is', null);
      if (periodId != null) {
        query = query.eq('evaluations.academic_period_id', periodId);
      }
      return await query.order('id').range(from, to);
    });
    return rows
        .map((r) => GradeEntry(
            evaluationId: r['evaluation_id'].toString(),
            studentId: (r['student_id'] as num).toInt(),
            rawScore: (r['score'] as num).toDouble(),
            notes: r['notes'] as String?,),)
        .toList();
  }

  Future<List<({int classId, String name, String teacher})>>
      _subjectsForStudent(int studentId) async {
    final rows = await _classesForStudent(studentId);
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
    return _performance(studentId: studentId, scale: scale);
  }

  Future<List<SubjectPerformance>> _performance(
      {required int studentId,
      GradingScale? scale,
      List<AcademicPeriod>? loadedPeriods,}) async {
    final initial = await Future.wait<dynamic>([
      scale == null ? defaultScale() : Future.value(scale),
      loadedPeriods == null ? periods() : Future.value(loadedPeriods),
      _subjectsForStudent(studentId),
      gradesFor(studentId: studentId),
    ]);
    final s = initial[0] as GradingScale;
    final periodsList = initial[1] as List<AcademicPeriod>;
    final subjects =
        initial[2] as List<({int classId, String name, String teacher})>;
    final myGrades = initial[3] as List<GradeEntry>;
    final gradesByEval = {
      for (final grade in myGrades) grade.evaluationId: grade,
    };
    final byClassPeriod = <(int, String), List<Evaluation>>{};
    for (final evaluation in await _evaluationsOfClasses(
        subjects.map((s) => s.classId).toList(),)) {
      byClassPeriod.putIfAbsent(
          (evaluation.classId, evaluation.periodId), () => [],).add(evaluation);
    }

    final result = <SubjectPerformance>[];
    for (final subj in subjects) {
      final periodGrades = <String, PeriodGrade>{};
      for (final p in periodsList) {
        final evals =
            byClassPeriod[(subj.classId, p.id)] ?? const <Evaluation>[];
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
    final initial = await Future.wait<dynamic>([
      scale == null ? defaultScale() : Future.value(scale),
      periods(),
    ]);
    final s = initial[0] as GradingScale,
        periodsList = initial[1] as List<AcademicPeriod>;
    final targetPeriod = periodId == null
        ? null
        : periodsList.firstWhere((p) => p.id == periodId);
    final values = await Future.wait<dynamic>([
      _performance(studentId: studentId, scale: s, loadedPeriods: periodsList),
      _c.rpc('student_report_context', params: {
        'p_student_id': studentId,
        'p_period_id': periodId,
      },).then<dynamic>((value) => value),
    ]);
    final performances = values[0] as List<SubjectPerformance>;
    final context = Map<String, dynamic>.from(values[1] as Map);
    final lines = <ReportCardLine>[];
    for (final perf in performances) {
      final score = targetPeriod == null
          ? perf.finalScore
          : (perf.periodScores[targetPeriod.id] ?? 0);
      final count = targetPeriod == null
          ? perf.evaluationCount
          : perf.periodEvaluationCounts[targetPeriod.id];
      lines.add(ReportCardLine(
          subjectName: perf.subjectName,
          teacherName: perf.teacherName,
          finalScore: score,
          evaluationCount: count,
          qualitativeLabel: count == 0 ? null : s.labelFor(score),
          passed: count != 0 && s.isPassing(score),),);
    }
    final overall = targetPeriod == null
        ? _calc.overallAverage(performances)
        : _calc.reportAverage(lines);
    return ReportCard(
        studentId: studentId,
        studentName: context['studentName'] as String? ?? 'Estudiante',
        institutionName: context['institutionName'] as String? ?? 'Colegio',
        gradeLevel: context['gradeLevel'] as String? ?? '—',
        periodName: targetPeriod?.name ?? 'Anual',
        periodStart: targetPeriod?.startDate ??
            DateTime.tryParse(context['yearStart'] as String? ?? '') ??
            DateTime(DateTime.now().year, 1, 1),
        periodEnd: targetPeriod?.endDate ??
            DateTime.tryParse(context['yearEnd'] as String? ?? '') ??
            DateTime(DateTime.now().year, 12, 31),
        lines: lines,
        overallAverage: overall,
        overallLabel:
            lines.any((line) => line.hasGrade) ? s.labelFor(overall) : null,
        attendancePct: (context['attendancePct'] as num?)?.toDouble(),
        rank: (context['rank'] as num?)?.toInt(),
        totalPeers: (context['totalPeers'] as num?)?.toInt(),);
  }

  // ---------- Gradebook ----------
  @override
  Future<GradebookMatrix> gradebook({
    required int classId,
    required String periodId,
  }) async {
    final data = Map<String, dynamic>.from(await _api.get('/grades/gradebook',
        queryParameters: {'classId': classId, 'periodId': periodId},) as Map,);
    final evaluations = (data['evaluations'] as List)
        .cast<Map<String, dynamic>>()
        .map((row) => Evaluation(
              id: row['id'].toString(),
              classId: classId,
              periodId: periodId,
              subjectName: row['subjectName'] as String? ?? 'Materia',
              title: row['title'] as String? ?? '',
              date: DateTime.tryParse(row['date'] as String? ?? '') ??
                  DateTime.now(),
              maxScore: (row['maxScore'] as num?)?.toDouble() ?? 100,
              weight: (row['weight'] as num?)?.toDouble() ?? 1,
              kind: row['kind'] as String? ?? 'homework',
            ),)
        .toList();
    return GradebookMatrix(
      evaluations: evaluations,
      students: (data['students'] as List)
          .cast<Map<String, dynamic>>()
          .map((row) => (
                studentId: int.parse(row['studentId'].toString()),
                name: row['name'] as String
              ),)
          .toList(),
      grades: (data['grades'] as Map<String, dynamic>).map((student, value) =>
          MapEntry(
              int.parse(student),
              Map<String, dynamic>.from(value as Map).map((evaluation, score) =>
                  MapEntry(evaluation, (score as num?)?.toDouble()),),),),
    );
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
