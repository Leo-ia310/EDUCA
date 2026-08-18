import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities.dart';
import '../../providers.dart';
import 'assignment_detail_controller.dart';
import 'assignments_list_controller.dart';

/// Acción puntual: calificar una entrega.
class GradingController extends StateNotifier<AsyncValue<Submission>?> {
  GradingController(this._ref) : super(null);
  final Ref _ref;

  Future<Submission?> grade({
    required String assignmentId,
    required String submissionId,
    required double score,
    String? feedback,
  }) async {
    state = const AsyncValue.loading();
    try {
      final result =
          await _ref.read(assignmentRepositoryProvider).gradeSubmission(
                submissionId: submissionId,
                score: score,
                feedback: feedback,
              );
      state = AsyncValue.data(result);
      _ref.invalidate(submissionsForAssignmentProvider(assignmentId));
      _ref.invalidate(assignmentByIdProvider(assignmentId));
      _ref.invalidate(teacherAssignmentsProvider);
      return result;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }
}

final gradingControllerProvider = StateNotifierProvider.autoDispose<
    GradingController, AsyncValue<Submission>?>((ref) {
  return GradingController(ref);
});
