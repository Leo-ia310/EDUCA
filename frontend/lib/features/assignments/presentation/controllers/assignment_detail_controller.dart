import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities.dart';
import '../../providers.dart';

/// Lee una tarea por id (autoDispose para no retener memoria).
final assignmentByIdProvider =
    FutureProvider.autoDispose.family<Assignment?, String>((ref, id) {
  return ref.watch(assignmentRepositoryProvider).assignmentById(id);
});

/// Lista de entregas de una tarea (vista docente).
final submissionsForAssignmentProvider = FutureProvider.autoDispose
    .family<List<Submission>, String>((ref, assignmentId) {
  return ref
      .watch(assignmentRepositoryProvider)
      .submissionsForAssignment(assignmentId);
});

/// Entrega del estudiante actual para una tarea.
final mySubmissionProvider = FutureProvider.autoDispose
    .family<Submission?, ({String assignmentId, int studentId})>(
        (ref, args) {
  return ref.watch(assignmentRepositoryProvider).submissionForStudent(
        assignmentId: args.assignmentId,
        studentId: args.studentId,
      );
});
