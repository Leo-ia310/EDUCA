import '../domain/entities.dart';
import '../domain/grades_calculator.dart';
import '../domain/grades_repository.dart';
import '../../assignments/data/mock_assignments_data.dart' show AssignmentsMockSeed;
import 'mock_grades_data.dart';

class MockGradesRepository implements GradesRepository {
  MockGradesRepository() {
    final scales = <GradingScale>[...GradesMockSeed.defaultScales];
    _scales.addAll(scales);
    _defaultScaleId =
        scales.firstWhere((s) => s.isDefault, orElse: () => scales.first).id;
    // Semillar evaluaciones + notas para el estudiante demo (1001).
    for (final studentId in AssignmentsMockSeed.studentNames.keys) {
      final seeded = GradesMockSeed.seedForStudent(studentId);
      _evaluations.addAll(seeded.evaluations);
      _grades.addAll(seeded.grades);
    }
  }

  final _scales = <GradingScale>[];
  late String _defaultScaleId;
  final _evaluations = <Evaluation>[];
  final _grades = <GradeEntry>[];
  final _calc = const GradesCalculator();

  // ---------- Escalas ----------
  @override
  Future<List<GradingScale>> scales() async => List.unmodifiable(_scales);

  @override
  Future<GradingScale> defaultScale() async =>
      _scales.firstWhere((s) => s.id == _defaultScaleId);

  @override
  Future<GradingScale> upsertScale(GradingScale scale) async {
    final idx = _scales.indexWhere((s) => s.id == scale.id);
    if (idx >= 0) {
      _scales[idx] = scale;
    } else {
      _scales.add(scale);
    }
    return scale;
  }

  @override
  Future<void> setDefaultScale(String id) async {
    if (_scales.any((s) => s.id == id)) _defaultScaleId = id;
  }

  // ---------- Periodos ----------
  @override
  Future<List<AcademicPeriod>> periods() async =>
      List.unmodifiable(GradesMockSeed.periods);

  // ---------- Evaluaciones ----------
  @override
  Future<List<Evaluation>> evaluationsFor({
    required int studentId,
    String? periodId,
    int? classId,
  }) async {
    return _evaluations.where((e) {
      if (periodId != null && e.periodId != periodId) return false;
      if (classId != null && e.classId != classId) return false;
      return true;
    }).toList();
  }

  @override
  Future<List<GradeEntry>> gradesFor({
    required int studentId,
    String? periodId,
  }) async {
    final validIds = periodId == null
        ? _evaluations.map((e) => e.id).toSet()
        : _evaluations
            .where((e) => e.periodId == periodId)
            .map((e) => e.id)
            .toSet();
    return _grades
        .where((g) => g.studentId == studentId && validIds.contains(g.evaluationId))
        .toList();
  }

  // ---------- Cálculos ----------
  @override
  Future<List<SubjectPerformance>> performanceForStudent({
    required int studentId,
    GradingScale? scale,
  }) async {
    final s = scale ?? await defaultScale();
    final periods = GradesMockSeed.periods;
    final subjects = GradesMockSeed.subjectsForStudent(studentId);
    final myGrades = await gradesFor(studentId: studentId);
    final gradesByEval = {for (final g in myGrades) g.evaluationId: g};

    final result = <SubjectPerformance>[];
    for (final subj in subjects) {
      final periodGrades = <String, PeriodGrade>{};
      for (final p in periods) {
        final evals = _evaluations
            .where((e) => e.classId == subj.classId && e.periodId == p.id)
            .toList();
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
      result.add(_calc.computeSubjectPerformance(
        subjectName: subj.name,
        teacherName: subj.teacher,
        periodGrades: periodGrades,
        periods: periods,
        scale: s,
      ));
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
    final periods = GradesMockSeed.periods;
    final targetPeriod = periodId == null
        ? null
        : periods.firstWhere((p) => p.id == periodId);
    final performances = await performanceForStudent(
      studentId: studentId,
      scale: s,
    );

    final lines = <ReportCardLine>[];
    for (final perf in performances) {
      final score = targetPeriod == null
          ? perf.finalScore
          : perf.periodScores[targetPeriod.id] ?? 0;
      lines.add(ReportCardLine(
        subjectName: perf.subjectName,
        teacherName: perf.teacherName,
        finalScore: score,
        qualitativeLabel: s.labelFor(score),
        passed: s.isPassing(score),
      ));
    }
    final overall = targetPeriod == null
        ? _calc.overallAverage(performances)
        : _averageOfLines(lines);

    return ReportCard(
      studentId: studentId,
      studentName:
          AssignmentsMockSeed.studentNames[studentId] ?? 'Estudiante',
      institutionName: 'Colegio Demo Educa360',
      gradeLevel: '4° Grado A',
      periodName: targetPeriod?.name ?? 'Anual',
      periodStart: targetPeriod?.startDate ?? DateTime(DateTime.now().year, 1, 1),
      periodEnd: targetPeriod?.endDate ?? DateTime(DateTime.now().year, 12, 31),
      lines: lines,
      overallAverage: overall,
      overallLabel: s.labelFor(overall),
      attendancePct: 96.5,
      rank: 3,
      totalPeers: 24,
    );
  }

  // ---------- Gradebook ----------
  @override
  Future<GradebookMatrix> gradebook({
    required int classId,
    required String periodId,
  }) async {
    final evaluations = _evaluations
        .where((e) => e.classId == classId && e.periodId == periodId)
        .toList();
    final studentIds = AssignmentsMockSeed.studentNames.keys.toList();
    final grades = <int, Map<String, double?>>{};
    for (final id in studentIds) {
      grades[id] = {};
      for (final e in evaluations) {
        final g = _grades.firstWhere(
          (gg) => gg.studentId == id && gg.evaluationId == e.id,
          orElse: () => const GradeEntry(
              evaluationId: '', studentId: -1, rawScore: -1),
        );
        grades[id]![e.id] = g.studentId == -1 ? null : g.rawScore;
      }
    }
    return GradebookMatrix(
      evaluations: evaluations,
      students: studentIds
          .map((id) =>
              (studentId: id, name: AssignmentsMockSeed.studentNames[id]!))
          .toList(),
      grades: grades,
    );
  }

  @override
  Future<void> setGrade({
    required String evaluationId,
    required int studentId,
    required double rawScore,
    String? notes,
  }) async {
    final idx = _grades.indexWhere(
      (g) => g.evaluationId == evaluationId && g.studentId == studentId,
    );
    final entry = GradeEntry(
      evaluationId: evaluationId,
      studentId: studentId,
      rawScore: rawScore,
      notes: notes,
    );
    if (idx == -1) {
      _grades.add(entry);
    } else {
      _grades[idx] = entry;
    }
  }

  // ---------- helpers ----------
  double _averageOfLines(List<ReportCardLine> lines) {
    final valid = lines.where((l) => l.finalScore > 0).toList();
    if (valid.isEmpty) return 0;
    final sum = valid.fold<double>(0, (a, l) => a + l.finalScore);
    return double.parse((sum / valid.length).toStringAsFixed(2));
  }
}
