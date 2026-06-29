import 'package:uuid/uuid.dart';

import '../domain/assignment_repository.dart';
import '../domain/entities.dart';
import 'mock_assignments_data.dart';

const _uuid = Uuid();

/// Repository en memoria para el modo demo. Mantiene tareas y entregas en
/// listas mutables y las refresca tras cada operación. Útil para que los
/// controllers consuman el flujo completo sin Supabase configurado.
class MockAssignmentRepository implements AssignmentRepository {
  MockAssignmentRepository();

  late final List<Assignment> _assignments =
      AssignmentsMockSeed.initialAssignments();

  /// Cache de entregas creadas a demanda al pedir submissions de una tarea.
  final Map<String, List<Submission>> _submissionsByAssignment = {};

  // ---------- Lectura ----------
  @override
  Future<List<Assignment>> assignmentsForTeacher({int? classId}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final list = classId == null
        ? _assignments
        : _assignments.where((a) => a.classId == classId).toList();
    return List.unmodifiable(_sorted(list));
  }

  @override
  Future<List<Assignment>> assignmentsForStudent({int? studentId}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_sorted(_assignments));
  }

  @override
  Future<Assignment?> assignmentById(String id) async {
    return _assignments.where((a) => a.id == id).cast<Assignment?>().firstOrNull;
  }

  @override
  Future<List<Submission>> submissionsForAssignment(String assignmentId) async {
    final list = _submissionsByAssignment.putIfAbsent(
      assignmentId,
      () {
        final a = _assignments.firstWhere(
          (x) => x.id == assignmentId,
          orElse: () => _assignments.first,
        );
        return AssignmentsMockSeed.initialSubmissionsFor(a);
      },
    );
    return List.unmodifiable(list);
  }

  @override
  Future<Submission?> submissionForStudent({
    required String assignmentId,
    required int studentId,
  }) async {
    final list = await submissionsForAssignment(assignmentId);
    return list.where((s) => s.studentId == studentId).cast<Submission?>().firstOrNull;
  }

  // ---------- Escritura docente ----------
  @override
  Future<Assignment> upsertAssignment(AssignmentDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final id = draft.assignmentId ?? 'a-${_uuid.v4().substring(0, 8)}';
    final idx = _assignments.indexWhere((a) => a.id == id);
    final existing = idx >= 0 ? _assignments[idx] : null;
    final created = Assignment(
      id: id,
      classId: draft.classId,
      subjectName: existing?.subjectName ?? _subjectForClass(draft.classId),
      groupName: existing?.groupName ?? _groupForClass(draft.classId),
      title: draft.title,
      description: draft.description,
      instructions: draft.instructions,
      assignedAt: existing?.assignedAt ?? DateTime.now(),
      dueAt: draft.dueAt,
      kind: draft.kind,
      maxScore: draft.maxScore,
      allowLate: draft.allowLate,
      published: draft.published,
      attachments: draft.attachments,
      teacherName: existing?.teacherName ?? 'Prof. Elena Ramírez',
      totalStudents: existing?.totalStudents ?? 24,
      submittedCount: existing?.submittedCount ?? 0,
      gradedCount: existing?.gradedCount ?? 0,
    );
    if (idx >= 0) {
      _assignments[idx] = created;
    } else {
      _assignments.add(created);
    }
    _submissionsByAssignment.remove(id);
    return created;
  }

  @override
  Future<void> deleteAssignment(String id) async {
    _assignments.removeWhere((a) => a.id == id);
    _submissionsByAssignment.remove(id);
  }

  @override
  Future<void> publishAssignment(String id, {required bool published}) async {
    final idx = _assignments.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    _assignments[idx] = _assignments[idx].copyWith(published: published);
  }

  @override
  Future<Submission> gradeSubmission({
    required String submissionId,
    required double score,
    String? feedback,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    Submission? updated;
    for (final entry in _submissionsByAssignment.entries) {
      final idx = entry.value.indexWhere((s) => s.id == submissionId);
      if (idx == -1) continue;
      final wasGraded = entry.value[idx].status == SubmissionStatus.graded;
      updated = entry.value[idx].copyWith(
        status: SubmissionStatus.graded,
        score: score,
        feedback: feedback,
        gradedAt: DateTime.now(),
        gradedBy: 'Prof. Elena Ramírez',
      );
      entry.value[idx] = updated;

      // Actualizar contador de la tarea.
      final aIdx = _assignments.indexWhere((a) => a.id == entry.key);
      if (aIdx >= 0 && !wasGraded) {
        final a = _assignments[aIdx];
        _assignments[aIdx] = a.copyWith(gradedCount: a.gradedCount + 1);
      }
      break;
    }
    return updated ??
        (throw StateError('Entrega $submissionId no encontrada'));
  }

  // ---------- Escritura estudiante ----------
  @override
  Future<Submission> submit({
    required String assignmentId,
    required int studentId,
    required List<AssignmentAttachment> attachments,
    String? notes,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final list = await submissionsForAssignment(assignmentId);
    final mutable = list.toList();
    final a = _assignments.firstWhere((x) => x.id == assignmentId);
    final isLate = DateTime.now().isAfter(a.dueAt);
    var idx = mutable.indexWhere((s) => s.studentId == studentId);
    final wasPending =
        idx == -1 || mutable[idx].status == SubmissionStatus.pending;
    final updated = Submission(
      id: idx == -1 ? _uuid.v4() : mutable[idx].id,
      assignmentId: assignmentId,
      studentId: studentId,
      studentName: idx == -1
          ? AssignmentsMockSeed.studentNames[studentId] ?? 'Estudiante'
          : mutable[idx].studentName,
      status: isLate ? SubmissionStatus.late : SubmissionStatus.submitted,
      submittedAt: DateTime.now(),
      studentNotes: notes,
      attachments: attachments,
    );
    if (idx == -1) {
      mutable.add(updated);
    } else {
      mutable[idx] = updated;
    }
    _submissionsByAssignment[assignmentId] = mutable;

    // Bump submittedCount si pasamos de pending → submitted.
    if (wasPending) {
      final ai = _assignments.indexWhere((x) => x.id == assignmentId);
      if (ai >= 0) {
        _assignments[ai] = _assignments[ai].copyWith(
          submittedCount: _assignments[ai].submittedCount + 1,
        );
      }
    }
    return updated;
  }

  // ---------- Counters ----------
  @override
  Future<({int pending, int submitted, int toGrade})> teacherCounters() async {
    var pending = 0, submitted = 0, toGrade = 0;
    final now = DateTime.now();
    for (final a in _assignments) {
      if (a.statusForNow(now) == AssignmentStatus.open ||
          a.statusForNow(now) == AssignmentStatus.dueSoon) {
        pending++;
      }
      submitted += a.submittedCount;
      toGrade += (a.submittedCount - a.gradedCount).clamp(0, a.submittedCount);
    }
    return (pending: pending, submitted: submitted, toGrade: toGrade);
  }

  @override
  Future<({int pending, int submitted, int graded})> studentCounters({
    required int studentId,
  }) async {
    var pending = 0, submitted = 0, graded = 0;
    for (final a in _assignments) {
      final s = (await submissionsForAssignment(a.id))
          .where((e) => e.studentId == studentId)
          .cast<Submission?>()
          .firstOrNull;
      switch (s?.status) {
        case SubmissionStatus.submitted:
        case SubmissionStatus.late:
          submitted++;
          break;
        case SubmissionStatus.graded:
        case SubmissionStatus.returned:
          graded++;
          break;
        case SubmissionStatus.pending:
        case null:
          pending++;
          break;
      }
    }
    return (pending: pending, submitted: submitted, graded: graded);
  }

  // ---------- Helpers ----------
  List<Assignment> _sorted(List<Assignment> list) {
    final copy = list.toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return copy;
  }

  String _subjectForClass(int classId) => switch (classId) {
        101 => 'Matemáticas Avanzadas',
        102 => 'Geometría',
        103 => 'Cálculo Diferencial',
        201 => 'Historia Universal',
        301 => 'Física Cuántica',
        401 => 'Ética',
        _ => 'Materia',
      };

  String _groupForClass(int classId) => switch (classId) {
        101 || 201 || 401 => '4° Grado A',
        102 => '4° Grado B',
        103 || 301 => '5° Grado A',
        _ => 'Grupo',
      };
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
