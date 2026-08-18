import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

/// Tipo de escala configurable por colegio.
enum ScaleType {
  /// Valor numérico continuo (ej. 0-100, 0-10).
  numeric,

  /// Etiqueta cualitativa (AA / AS / AE / AI del MINED).
  qualitative,

  /// Letras (A, B, C…).
  letters;
}

/// Rango de una escala. Para escalas cualitativas define la etiqueta que
/// corresponde a cada tramo del valor calculado.
class ScaleRange extends Equatable {
  const ScaleRange({
    required this.label,
    required this.rangeMin,
    required this.rangeMax,
    required this.passed,
    this.description,
    this.color,
  });

  final String label;
  final double rangeMin;
  final double rangeMax;
  final bool passed;
  final String? description;
  final Color? color;

  bool contains(double value) => value >= rangeMin && value <= rangeMax;

  @override
  List<Object?> get props => [label, rangeMin, rangeMax, passed];
}

/// Escala de calificación configurada por el colegio. Las escalas son
/// mutables desde el rol admin (ver [ScalesController]).
class GradingScale extends Equatable {
  const GradingScale({
    required this.id,
    required this.name,
    required this.type,
    required this.minValue,
    required this.maxValue,
    required this.passValue,
    required this.decimals,
    required this.ranges,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final ScaleType type;
  final double minValue;
  final double maxValue;
  final double passValue;
  final int decimals;
  final List<ScaleRange> ranges;
  final bool isDefault;

  /// Convierte un valor numérico crudo al valor de esta escala. Ej.: si el
  /// crudo viene en 0-100 y esta escala trabaja 0-10, escala linealmente.
  double normalize(double raw, {double rawMax = 100}) {
    if (rawMax == 0) return minValue;
    final ratio = (raw / rawMax).clamp(0, 1).toDouble();
    return (minValue + ratio * (maxValue - minValue))
        .toDouble()
        .toStringAsFixed(decimals)
        .let(double.parse);
  }

  /// Etiqueta cualitativa para un valor ya en la escala.
  String? labelFor(double value) {
    for (final r in ranges) {
      if (r.contains(value)) return r.label;
    }
    return null;
  }

  bool isPassing(double value) => value >= passValue;

  @override
  List<Object?> get props =>
      [id, name, type, minValue, maxValue, passValue];
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Periodo académico. En modo demo hay 3 periodos por año (trimestres).
class AcademicPeriod extends Equatable {
  const AcademicPeriod({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.weight,
    this.closed = false,
    this.isCurrent = false,
  });

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final double weight;
  final bool closed;
  final bool isCurrent;

  @override
  List<Object?> get props => [id, name, startDate, endDate];
}

/// Evaluación puntual de una materia dentro de un periodo. Fuente de datos
/// para calcular la nota del periodo.
class Evaluation extends Equatable {
  const Evaluation({
    required this.id,
    required this.classId,
    required this.subjectName,
    required this.periodId,
    required this.title,
    required this.date,
    required this.maxScore,
    required this.weight,
    this.kind = 'homework',
  });

  final String id;
  final int classId;
  final String subjectName;
  final String periodId;
  final String title;
  final DateTime date;
  final double maxScore;
  final double weight;
  final String kind;

  @override
  List<Object?> get props => [id, title, date, weight];
}

/// Nota registrada de un estudiante en una evaluación.
class GradeEntry extends Equatable {
  const GradeEntry({
    required this.evaluationId,
    required this.studentId,
    required this.rawScore,
    this.notes,
  });

  final String evaluationId;
  final int studentId;
  final double rawScore;
  final String? notes;

  @override
  List<Object?> get props => [evaluationId, studentId, rawScore];
}

/// Nota calculada del estudiante para una materia en un periodo. Se deriva
/// de las evaluaciones vía [GradesCalculator]. Puede o no persistirse en
/// `period_grades`.
class PeriodGrade extends Equatable {
  const PeriodGrade({
    required this.studentId,
    required this.subjectName,
    required this.periodId,
    required this.score,
    required this.qualitativeLabel,
    required this.passed,
    required this.evaluationCount,
  });

  final int studentId;
  final String subjectName;
  final String periodId;
  final double score;
  final String? qualitativeLabel;
  final bool passed;
  final int evaluationCount;

  @override
  List<Object?> get props => [studentId, subjectName, periodId, score];
}

/// Rendimiento consolidado de un estudiante en una materia a lo largo del
/// año académico.
class SubjectPerformance extends Equatable {
  const SubjectPerformance({
    required this.subjectName,
    required this.teacherName,
    required this.periodScores,
    required this.finalScore,
    required this.qualitativeLabel,
    required this.passed,
    required this.evaluationCount,
  });

  final String subjectName;
  final String teacherName;
  final Map<String, double> periodScores;
  final double finalScore;
  final String? qualitativeLabel;
  final bool passed;
  final int evaluationCount;

  double get bestPeriod =>
      periodScores.values.isEmpty ? 0 : periodScores.values.reduce((a, b) => a > b ? a : b);
  double get worstPeriod =>
      periodScores.values.isEmpty ? 0 : periodScores.values.reduce((a, b) => a < b ? a : b);

  @override
  List<Object?> get props => [subjectName, finalScore, periodScores];
}

/// Boletín consolidado del estudiante para un periodo (o anual si
/// `periodId == null`).
class ReportCard extends Equatable {
  const ReportCard({
    required this.studentId,
    required this.studentName,
    required this.institutionName,
    required this.gradeLevel,
    required this.periodName,
    required this.periodStart,
    required this.periodEnd,
    required this.lines,
    required this.overallAverage,
    required this.overallLabel,
    required this.attendancePct,
    required this.rank,
    required this.totalPeers,
  });

  final int studentId;
  final String studentName;
  final String institutionName;
  final String gradeLevel;
  final String periodName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<ReportCardLine> lines;
  final double overallAverage;
  final String? overallLabel;
  final double attendancePct;
  final int rank;
  final int totalPeers;

  @override
  List<Object?> get props =>
      [studentId, periodName, overallAverage, lines];
}

class ReportCardLine extends Equatable {
  const ReportCardLine({
    required this.subjectName,
    required this.teacherName,
    required this.finalScore,
    required this.qualitativeLabel,
    required this.passed,
    this.notes,
  });

  final String subjectName;
  final String teacherName;
  final double finalScore;
  final String? qualitativeLabel;
  final bool passed;
  final String? notes;

  @override
  List<Object?> get props => [subjectName, finalScore, passed];
}
