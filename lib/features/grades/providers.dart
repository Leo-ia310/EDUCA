import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/mock_grades_repository.dart';
import 'domain/entities.dart';
import 'domain/grades_calculator.dart';
import 'domain/grades_repository.dart';

/// Singleton para que las escalas y notas registradas desde admin/docente
/// persistan durante toda la sesión demo.
final gradesRepositoryProvider = Provider<GradesRepository>((ref) {
  return MockGradesRepository();
});

final gradesCalculatorProvider =
    Provider<GradesCalculator>((ref) => const GradesCalculator());

/// Escalas configuradas por el colegio.
final scalesProvider =
    FutureProvider<List<GradingScale>>((ref) async =>
        ref.watch(gradesRepositoryProvider).scales());

final defaultScaleProvider = FutureProvider<GradingScale>(
  (ref) async => ref.watch(gradesRepositoryProvider).defaultScale(),
);

final periodsProvider = FutureProvider<List<AcademicPeriod>>((ref) async {
  return ref.watch(gradesRepositoryProvider).periods();
});

/// Periodo actualmente seleccionado en la UI. `null` = vista anual.
final selectedPeriodIdProvider = StateProvider<String?>((ref) => null);
