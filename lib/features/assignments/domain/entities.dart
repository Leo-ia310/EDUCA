import 'package:equatable/equatable.dart';

/// Tipo de actividad. Mapea a `catalog_evaluation_types`.
enum AssignmentKind {
  homework('Tarea'),
  exam('Examen'),
  project('Proyecto'),
  quiz('Quiz'),
  presentation('Exposición');

  const AssignmentKind(this.label);
  final String label;
}

/// Estado calculado de una tarea para una vista. Se deriva — no se persiste —
/// salvo donde el server tenga su propio status (cerrada, archivada).
enum AssignmentStatus {
  draft('Borrador'),
  open('Abierta'),
  dueSoon('Vence pronto'),
  overdue('Vencida'),
  closed('Cerrada');

  const AssignmentStatus(this.label);
  final String label;
}

/// Archivo adjunto a una tarea o a una entrega. En modo demo `url` puede ser
/// un `file://` local. En producción es una URL firmada de Supabase Storage.
class AssignmentAttachment extends Equatable {
  const AssignmentAttachment({
    required this.id,
    required this.name,
    required this.url,
    this.sizeBytes,
    this.mimeType,
  });

  final String id;
  final String name;
  final String url;
  final int? sizeBytes;
  final String? mimeType;

  bool get isImage =>
      mimeType?.startsWith('image/') == true ||
      const ['jpg', 'jpeg', 'png', 'webp', 'gif']
          .any(name.toLowerCase().endsWith);

  String get extension {
    final i = name.lastIndexOf('.');
    if (i == -1 || i == name.length - 1) return '';
    return name.substring(i + 1).toUpperCase();
  }

  @override
  List<Object?> get props => [id, name, url];
}

/// Resumen de tarea para listas y feeds.
class Assignment extends Equatable {
  const Assignment({
    required this.id,
    required this.classId,
    required this.subjectName,
    required this.groupName,
    required this.title,
    required this.assignedAt,
    required this.dueAt,
    required this.kind,
    required this.maxScore,
    required this.allowLate,
    required this.attachments,
    required this.totalStudents,
    required this.submittedCount,
    required this.gradedCount,
    this.description,
    this.instructions,
    this.teacherName,
    this.published = true,
  });

  final String id;
  final int classId;
  final String subjectName;
  final String groupName;
  final String title;
  final String? description;
  final String? instructions;
  final DateTime assignedAt;
  final DateTime dueAt;
  final AssignmentKind kind;
  final double maxScore;
  final bool allowLate;
  final bool published;
  final List<AssignmentAttachment> attachments;
  final String? teacherName;

  /// Para la vista del docente.
  final int totalStudents;
  final int submittedCount;
  final int gradedCount;

  AssignmentStatus statusForNow(DateTime now) {
    if (!published) return AssignmentStatus.draft;
    if (gradedCount >= totalStudents && totalStudents > 0) {
      return AssignmentStatus.closed;
    }
    if (now.isAfter(dueAt)) return AssignmentStatus.overdue;
    if (dueAt.difference(now).inHours <= 48) return AssignmentStatus.dueSoon;
    return AssignmentStatus.open;
  }

  double get submissionProgress =>
      totalStudents == 0 ? 0 : submittedCount / totalStudents;
  double get gradingProgress =>
      submittedCount == 0 ? 0 : gradedCount / submittedCount;

  Assignment copyWith({
    String? title,
    String? description,
    String? instructions,
    DateTime? assignedAt,
    DateTime? dueAt,
    AssignmentKind? kind,
    double? maxScore,
    bool? allowLate,
    bool? published,
    List<AssignmentAttachment>? attachments,
    int? submittedCount,
    int? gradedCount,
  }) {
    return Assignment(
      id: id,
      classId: classId,
      subjectName: subjectName,
      groupName: groupName,
      title: title ?? this.title,
      description: description ?? this.description,
      instructions: instructions ?? this.instructions,
      assignedAt: assignedAt ?? this.assignedAt,
      dueAt: dueAt ?? this.dueAt,
      kind: kind ?? this.kind,
      maxScore: maxScore ?? this.maxScore,
      allowLate: allowLate ?? this.allowLate,
      published: published ?? this.published,
      attachments: attachments ?? this.attachments,
      teacherName: teacherName,
      totalStudents: totalStudents,
      submittedCount: submittedCount ?? this.submittedCount,
      gradedCount: gradedCount ?? this.gradedCount,
    );
  }

  @override
  List<Object?> get props => [id, title, dueAt, submittedCount, gradedCount];
}

/// Estado de entrega del estudiante.
enum SubmissionStatus {
  pending('Pendiente'),
  submitted('Entregada'),
  late('Tarde'),
  graded('Calificada'),
  returned('Devuelta');

  const SubmissionStatus(this.label);
  final String label;
}

class Submission extends Equatable {
  const Submission({
    required this.id,
    required this.assignmentId,
    required this.studentId,
    required this.studentName,
    required this.status,
    required this.attachments,
    this.submittedAt,
    this.studentNotes,
    this.score,
    this.feedback,
    this.gradedAt,
    this.gradedBy,
    this.avatarUrl,
  });

  final String id;
  final String assignmentId;
  final int studentId;
  final String studentName;
  final String? avatarUrl;
  final SubmissionStatus status;
  final DateTime? submittedAt;
  final String? studentNotes;
  final List<AssignmentAttachment> attachments;
  final double? score;
  final String? feedback;
  final DateTime? gradedAt;
  final String? gradedBy;

  bool get isLate => status == SubmissionStatus.late;
  bool get hasGrade => score != null;

  Submission copyWith({
    SubmissionStatus? status,
    DateTime? submittedAt,
    String? studentNotes,
    List<AssignmentAttachment>? attachments,
    double? score,
    String? feedback,
    DateTime? gradedAt,
    String? gradedBy,
  }) {
    return Submission(
      id: id,
      assignmentId: assignmentId,
      studentId: studentId,
      studentName: studentName,
      avatarUrl: avatarUrl,
      status: status ?? this.status,
      submittedAt: submittedAt ?? this.submittedAt,
      studentNotes: studentNotes ?? this.studentNotes,
      attachments: attachments ?? this.attachments,
      score: score ?? this.score,
      feedback: feedback ?? this.feedback,
      gradedAt: gradedAt ?? this.gradedAt,
      gradedBy: gradedBy ?? this.gradedBy,
    );
  }

  @override
  List<Object?> get props =>
      [id, status, submittedAt, score, feedback, gradedAt];
}

/// DTO para crear una tarea desde el form. Lo levanta el repository.
class AssignmentDraft {
  AssignmentDraft({
    required this.classId,
    required this.title,
    required this.kind,
    required this.dueAt,
    required this.maxScore,
    this.description,
    this.instructions,
    this.allowLate = false,
    this.published = true,
    this.attachments = const [],
    this.assignmentId,
  });

  final int classId;
  final String? assignmentId;
  final String title;
  final String? description;
  final String? instructions;
  final AssignmentKind kind;
  final DateTime dueAt;
  final double maxScore;
  final bool allowLate;
  final bool published;
  final List<AssignmentAttachment> attachments;
}
