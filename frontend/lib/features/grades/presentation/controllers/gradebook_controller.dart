import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/provider_cache.dart';
import '../../../dashboard/providers.dart';
import 'grades_controller.dart';

import '../../domain/grades_repository.dart';
import '../../providers.dart';

class GradebookArgs extends Equatable {
  const GradebookArgs({required this.classId, required this.periodId});
  final int classId;
  final String periodId;

  @override
  List<Object?> get props => [classId, periodId];
}

final gradebookProvider = FutureProvider.autoDispose
    .family<GradebookMatrix, GradebookArgs>((ref, args) async {
  return ref.cacheFor(
    ref
        .watch(gradesRepositoryProvider)
        .gradebook(classId: args.classId, periodId: args.periodId),
  );
});

final gradebookSaverProvider = Provider((ref) {
  return _GradebookSaver(ref);
});

class _GradebookSaver {
  _GradebookSaver(this._ref);
  final Ref _ref;

  Future<void> setGrade({
    required String evaluationId,
    required int studentId,
    required double rawScore,
    required GradebookArgs args,
  }) async {
    await _ref.read(gradesRepositoryProvider).setGrade(
          evaluationId: evaluationId,
          studentId: studentId,
          rawScore: rawScore,
        );
    _ref.invalidate(gradebookProvider(args));
    _ref.invalidate(studentPerformanceProvider(studentId));
    _ref.invalidate(
      reportCardProvider(
        StudentGradesArgs(studentId: studentId, periodId: args.periodId),
      ),
    );
    _ref.invalidate(
      reportCardProvider(StudentGradesArgs(studentId: studentId)),
    );
    _ref.invalidate(
      studentEvaluationsProvider(
        (studentId: studentId, classId: args.classId),
      ),
    );
    _ref.invalidate(teacherDashboardProvider);
  }
}
