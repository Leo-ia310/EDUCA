import 'package:educa360/features/grades/data/mock_grades_repository.dart';
import 'package:educa360/features/grades/domain/entities.dart';
import 'package:educa360/features/grades/domain/grades_repository.dart';
import 'package:educa360/features/grades/presentation/controllers/gradebook_controller.dart';
import 'package:educa360/features/grades/presentation/controllers/grades_controller.dart';
import 'package:educa360/features/grades/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Grades extends MockGradesRepository {
  int scaleReads = 0;
  final performances = <int, int>{};
  final books = <int, int>{};
  @override
  Future<GradingScale?> findDefaultScale() {
    scaleReads++;
    return super.findDefaultScale();
  }

  @override
  Future<List<SubjectPerformance>> performanceForStudent({
    required int studentId,
    GradingScale? scale,
  }) async {
    performances.update(studentId, (v) => v + 1, ifAbsent: () => 1);
    return [];
  }

  @override
  Future<GradebookMatrix> gradebook({
    required int classId,
    required String periodId,
  }) async {
    books.update(classId, (v) => v + 1, ifAbsent: () => 1);
    return const GradebookMatrix(evaluations: [], students: [], grades: {});
  }

  @override
  Future<void> setGrade({
    required String evaluationId,
    required int studentId,
    required double rawScore,
    String? notes,
  }) async {}
}

void main() {
  test(
      'grade navigation and concurrent consumers share scale and performance reads',
      () async {
    final repo = _Grades();
    final container = ProviderContainer(
      overrides: [gradesRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    for (var visit = 0; visit < 3; visit++) {
      final first = container.listen(studentPerformanceProvider(7), (_, __) {});
      final second =
          container.listen(studentPerformanceProvider(8), (_, __) {});
      await Future.wait([
        container.read(studentPerformanceProvider(7).future),
        container.read(studentPerformanceProvider(8).future),
      ]);
      first.close();
      second.close();
      await container.pump();
    }
    expect(repo.scaleReads, 1);
    expect(repo.performances, {7: 1, 8: 1});
  });

  test(
      'grade save invalidates affected student and class, preserves unrelated data',
      () async {
    final repo = _Grades();
    final container = ProviderContainer(
      overrides: [gradesRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    const args = GradebookArgs(classId: 1, periodId: '1');
    const other = GradebookArgs(classId: 2, periodId: '1');
    container.listen(studentPerformanceProvider(7), (_, __) {});
    container.listen(studentPerformanceProvider(8), (_, __) {});
    container.listen(gradebookProvider(args), (_, __) {});
    container.listen(gradebookProvider(other), (_, __) {});
    await Future.wait([
      container.read(studentPerformanceProvider(7).future),
      container.read(studentPerformanceProvider(8).future),
      container.read(gradebookProvider(args).future),
      container.read(gradebookProvider(other).future),
    ]);
    expect(repo.performances, {7: 1, 8: 1}, reason: 'before mutation');
    await container.read(gradebookSaverProvider).setGrade(
          evaluationId: '1',
          studentId: 7,
          rawScore: 90,
          args: args,
        );
    await container.read(studentPerformanceProvider(7).future);
    await container.read(gradebookProvider(args).future);
    expect(repo.performances, {7: 2, 8: 1});
    expect(repo.books, {1: 2, 2: 1});
    expect(repo.scaleReads, 1);
  });
}
