import 'package:uuid/uuid.dart';

import '../domain/entities.dart';

const _uuid = Uuid();

DateTime _now() => DateTime.now();
DateTime _daysFromNow(int days) =>
    DateTime.now().add(Duration(days: days)).copyWith(hour: 23, minute: 59);
DateTime _daysAgo(int days) =>
    DateTime.now().subtract(Duration(days: days));

/// Dataset inicial para el modo demo. Se mutará en memoria por el repository.
/// Las ids son strings estables para que las pantallas puedan navegar entre
/// sesiones sin perder el contexto.
class AssignmentsMockSeed {
  AssignmentsMockSeed._();

  static List<Assignment> initialAssignments() => <Assignment>[
        Assignment(
          id: 'a-mat-001',
          classId: 101,
          subjectName: 'Matemáticas Avanzadas',
          groupName: '4° Grado A',
          title: 'Examen Parcial II',
          description: 'Examen escrito sobre ecuaciones diferenciales lineales.',
          instructions:
              '60 minutos. Permitido un formulario de 1 página. Calculadora científica permitida.',
          assignedAt: _daysAgo(5),
          dueAt: _daysFromNow(1),
          kind: AssignmentKind.exam,
          maxScore: 100,
          allowLate: false,
          attachments: const [
            AssignmentAttachment(
              id: 'att-mat-001',
              name: 'Temario_Parcial_II.pdf',
              url: 'demo://files/Temario_Parcial_II.pdf',
              sizeBytes: 248_000,
              mimeType: 'application/pdf',
            ),
          ],
          teacherName: 'Prof. Elena Ramírez',
          totalStudents: 24,
          submittedCount: 12,
          gradedCount: 0,
        ),
        Assignment(
          id: 'a-mat-002',
          classId: 101,
          subjectName: 'Matemáticas Avanzadas',
          groupName: '4° Grado A',
          title: 'Práctica de Ecuaciones',
          description:
              'Resolver los 20 ejercicios del capítulo 4 y subirlos como PDF.',
          assignedAt: _daysAgo(8),
          dueAt: _daysFromNow(7),
          kind: AssignmentKind.homework,
          maxScore: 20,
          allowLate: true,
          attachments: const [],
          teacherName: 'Prof. Elena Ramírez',
          totalStudents: 24,
          submittedCount: 20,
          gradedCount: 8,
        ),
        Assignment(
          id: 'a-his-001',
          classId: 201,
          subjectName: 'Historia Universal',
          groupName: '4° Grado A',
          title: 'Ensayo: Revolución Industrial',
          description:
              'Ensayo de 800 palabras sobre los efectos económicos de la Revolución Industrial.',
          instructions:
              'Formato APA. Mínimo 3 referencias. Subir en PDF.',
          assignedAt: _daysAgo(2),
          dueAt: _daysFromNow(5),
          kind: AssignmentKind.homework,
          maxScore: 10,
          allowLate: false,
          attachments: const [],
          teacherName: 'Prof. Marilus Olivar',
          totalStudents: 24,
          submittedCount: 4,
          gradedCount: 0,
        ),
        Assignment(
          id: 'a-fis-001',
          classId: 301,
          subjectName: 'Física Cuántica',
          groupName: '5° Grado A',
          title: 'Investigación: Termodinámica',
          assignedAt: _daysAgo(12),
          dueAt: _daysAgo(2),
          kind: AssignmentKind.project,
          maxScore: 100,
          allowLate: true,
          attachments: const [],
          teacherName: 'Prof. Carlos Mendoza',
          totalStudents: 18,
          submittedCount: 18,
          gradedCount: 18,
        ),
        Assignment(
          id: 'a-etica-001',
          classId: 401,
          subjectName: 'Ética',
          groupName: '4° Grado A',
          title: 'Ensayo de Ética',
          description:
              'Ensayo de 500 palabras sobre dilemas éticos contemporáneos.',
          assignedAt: _daysAgo(3),
          dueAt: _daysFromNow(2),
          kind: AssignmentKind.homework,
          maxScore: 100,
          allowLate: true,
          attachments: const [],
          teacherName: 'Prof. Sara Núñez',
          totalStudents: 24,
          submittedCount: 8,
          gradedCount: 0,
        ),
        Assignment(
          id: 'a-mat-003',
          classId: 101,
          subjectName: 'Matemáticas Avanzadas',
          groupName: '4° Grado A',
          title: 'Quiz: Derivadas básicas',
          assignedAt: _daysAgo(20),
          dueAt: _daysAgo(15),
          kind: AssignmentKind.quiz,
          maxScore: 10,
          allowLate: false,
          attachments: const [],
          teacherName: 'Prof. Elena Ramírez',
          totalStudents: 24,
          submittedCount: 22,
          gradedCount: 22,
        ),
      ];

  /// Roster mínimo para que la pantalla de calificación tenga estudiantes.
  static const studentNames = <int, String>{
    1001: 'Ana Martínez',
    1002: 'Bruno García',
    1003: 'Carla López',
    1004: 'Diego Rivas',
    1005: 'Elena Soto',
    1006: 'Felipe Méndez',
    1007: 'Gabriela Ruiz',
    1008: 'Hugo Padilla',
    1009: 'Isabel Vargas',
    1010: 'Javier Sosa',
    1011: 'Karla Núñez',
    1012: 'Luis Herrera',
  };

  /// Genera entregas iniciales para una tarea según su `submittedCount` y
  /// `gradedCount`. Estable para mismas ids → comportamiento determinista.
  static List<Submission> initialSubmissionsFor(Assignment a) {
    final names = studentNames.entries.toList();
    return [
      for (var i = 0; i < a.totalStudents.clamp(0, names.length); i++)
        _buildSubmission(a, names[i].key, names[i].value, i),
    ];
  }

  static Submission _buildSubmission(
    Assignment a,
    int studentId,
    String name,
    int index,
  ) {
    final isSubmitted = index < a.submittedCount;
    final isGraded = index < a.gradedCount;
    SubmissionStatus status;
    if (isGraded) {
      status = SubmissionStatus.graded;
    } else if (isSubmitted) {
      status = a.dueAt.isBefore(_now()) && a.allowLate
          ? SubmissionStatus.late
          : SubmissionStatus.submitted;
    } else {
      status = SubmissionStatus.pending;
    }

    return Submission(
      id: 's-${a.id}-$studentId',
      assignmentId: a.id,
      studentId: studentId,
      studentName: name,
      status: status,
      submittedAt: isSubmitted
          ? a.dueAt.subtract(Duration(hours: index + 1))
          : null,
      attachments: isSubmitted
          ? [
              AssignmentAttachment(
                id: _uuid.v4(),
                name: 'entrega_$name.pdf'
                    .replaceAll(' ', '_')
                    .toLowerCase(),
                url: 'demo://files/entrega_$studentId.pdf',
                sizeBytes: 100_000 + index * 5000,
                mimeType: 'application/pdf',
              ),
            ]
          : const [],
      score: isGraded
          ? (a.maxScore * (0.6 + (index % 5) * 0.08)).clamp(0, a.maxScore)
          : null,
      feedback: isGraded ? 'Buen trabajo, revisa el ejercicio 3.' : null,
      gradedAt: isGraded ? a.dueAt.add(const Duration(days: 1)) : null,
      gradedBy: isGraded ? 'Prof. Elena Ramírez' : null,
    );
  }
}
