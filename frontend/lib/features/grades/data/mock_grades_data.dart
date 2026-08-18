import 'package:flutter/material.dart';

import '../domain/entities.dart';

/// Datos iniciales del módulo notas para el modo demo.
class GradesMockSeed {
  GradesMockSeed._();

  // ---------- Escalas ----------
  static const defaultScales = <GradingScale>[
    GradingScale(
      id: 'numeric-100',
      name: 'Numérica 0-100',
      type: ScaleType.numeric,
      minValue: 0,
      maxValue: 100,
      passValue: 60,
      decimals: 1,
      isDefault: true,
      ranges: [
        ScaleRange(
          label: 'Excelente',
          rangeMin: 90,
          rangeMax: 100,
          passed: true,
          color: Color(0xFF22C55E),
        ),
        ScaleRange(
          label: 'Muy bueno',
          rangeMin: 80,
          rangeMax: 89.99,
          passed: true,
          color: Color(0xFF3B82F6),
        ),
        ScaleRange(
          label: 'Bueno',
          rangeMin: 70,
          rangeMax: 79.99,
          passed: true,
          color: Color(0xFF9BE000),
        ),
        ScaleRange(
          label: 'Aprobado',
          rangeMin: 60,
          rangeMax: 69.99,
          passed: true,
          color: Color(0xFFF59E0B),
        ),
        ScaleRange(
          label: 'Reprobado',
          rangeMin: 0,
          rangeMax: 59.99,
          passed: false,
          color: Color(0xFFEF4444),
        ),
      ],
    ),
    GradingScale(
      id: 'numeric-10',
      name: 'Numérica 0-10',
      type: ScaleType.numeric,
      minValue: 0,
      maxValue: 10,
      passValue: 6,
      decimals: 1,
      ranges: [
        ScaleRange(label: 'Excelente', rangeMin: 9, rangeMax: 10, passed: true, color: Color(0xFF22C55E)),
        ScaleRange(label: 'Muy bueno', rangeMin: 8, rangeMax: 8.99, passed: true, color: Color(0xFF3B82F6)),
        ScaleRange(label: 'Bueno', rangeMin: 7, rangeMax: 7.99, passed: true, color: Color(0xFF9BE000)),
        ScaleRange(label: 'Aprobado', rangeMin: 6, rangeMax: 6.99, passed: true, color: Color(0xFFF59E0B)),
        ScaleRange(label: 'Reprobado', rangeMin: 0, rangeMax: 5.99, passed: false, color: Color(0xFFEF4444)),
      ],
    ),
    GradingScale(
      id: 'mined-qualitative',
      name: 'MINED Cualitativa',
      type: ScaleType.qualitative,
      minValue: 0,
      maxValue: 100,
      passValue: 60,
      decimals: 0,
      ranges: [
        ScaleRange(
          label: 'AA',
          rangeMin: 90,
          rangeMax: 100,
          passed: true,
          description: 'Aprendizaje Avanzado',
          color: Color(0xFF22C55E),
        ),
        ScaleRange(
          label: 'AS',
          rangeMin: 76,
          rangeMax: 89.99,
          passed: true,
          description: 'Aprendizaje Satisfactorio',
          color: Color(0xFF3B82F6),
        ),
        ScaleRange(
          label: 'AE',
          rangeMin: 60,
          rangeMax: 75.99,
          passed: true,
          description: 'Aprendizaje Elemental',
          color: Color(0xFFF59E0B),
        ),
        ScaleRange(
          label: 'AI',
          rangeMin: 0,
          rangeMax: 59.99,
          passed: false,
          description: 'Aprendizaje Inicial',
          color: Color(0xFFEF4444),
        ),
      ],
    ),
  ];

  // ---------- Periodos ----------
  static final periods = <AcademicPeriod>[
    AcademicPeriod(
      id: 'p1',
      name: 'I Trimestre',
      startDate: DateTime(2026, 2, 1),
      endDate: DateTime(2026, 5, 15),
      weight: 33.33,
      closed: true,
    ),
    AcademicPeriod(
      id: 'p2',
      name: 'II Trimestre',
      startDate: DateTime(2026, 5, 16),
      endDate: DateTime(2026, 8, 31),
      weight: 33.33,
      isCurrent: true,
    ),
    AcademicPeriod(
      id: 'p3',
      name: 'III Trimestre',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 12, 15),
      weight: 33.34,
    ),
  ];

  // ---------- Materias del estudiante demo ----------
  static const _subjects = <_SubjectSeed>[
    _SubjectSeed(
      classId: 101,
      name: 'Matemáticas Avanzadas',
      teacher: 'Prof. Elena Ramírez',
      // Evaluaciones por periodo (nota base sobre 100).
      periodScores: {
        'p1': [88.0, 92.0, 85.0, 90.0],
        'p2': [94.0, 90.0, 88.0],
        'p3': <double>[],
      },
    ),
    _SubjectSeed(
      classId: 201,
      name: 'Historia Universal',
      teacher: 'Prof. Marilus Olivar',
      periodScores: {
        'p1': [82.0, 85.0, 78.0],
        'p2': [88.0, 84.0],
        'p3': <double>[],
      },
    ),
    _SubjectSeed(
      classId: 301,
      name: 'Física Cuántica',
      teacher: 'Prof. Carlos Mendoza',
      periodScores: {
        'p1': [75.0, 72.0, 80.0, 78.0],
        'p2': [82.0, 78.0],
        'p3': <double>[],
      },
    ),
    _SubjectSeed(
      classId: 401,
      name: 'Ética',
      teacher: 'Prof. Sara Núñez',
      periodScores: {
        'p1': [95.0, 92.0],
        'p2': [90.0],
        'p3': <double>[],
      },
    ),
    _SubjectSeed(
      classId: 501,
      name: 'Biología Celular',
      teacher: 'Prof. Elena Santís',
      periodScores: {
        'p1': [85.0, 82.0, 88.0],
        'p2': [86.0, 84.0],
        'p3': <double>[],
      },
    ),
  ];

  /// Genera todas las evaluaciones + notas del estudiante demo (id=1001).
  /// Devuelve tuplas planas para que el repository las despache.
  static ({List<Evaluation> evaluations, List<GradeEntry> grades})
      seedForStudent(int studentId) {
    final evaluations = <Evaluation>[];
    final grades = <GradeEntry>[];
    var counter = 0;
    for (final s in _subjects) {
      for (final entry in s.periodScores.entries) {
        final periodId = entry.key;
        for (var i = 0; i < entry.value.length; i++) {
          final id = 'ev-${s.classId}-$periodId-${i + 1}';
          evaluations.add(Evaluation(
            id: id,
            classId: s.classId,
            subjectName: s.name,
            periodId: periodId,
            title: 'Actividad ${i + 1}',
            date: DateTime.now().subtract(Duration(days: 90 - counter)),
            maxScore: 100,
            weight: 1,
            kind: i.isEven ? 'homework' : 'exam',
          ));
          grades.add(GradeEntry(
            evaluationId: id,
            studentId: studentId,
            rawScore: entry.value[i],
          ));
          counter++;
        }
      }
    }
    return (evaluations: evaluations, grades: grades);
  }

  static List<({int classId, String name, String teacher})>
      subjectsForStudent(int studentId) => _subjects
          .map((s) =>
              (classId: s.classId, name: s.name, teacher: s.teacher))
          .toList();
}

class _SubjectSeed {
  const _SubjectSeed({
    required this.classId,
    required this.name,
    required this.teacher,
    required this.periodScores,
  });
  final int classId;
  final String name;
  final String teacher;
  final Map<String, List<double>> periodScores;
}
