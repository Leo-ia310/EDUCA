import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/supabase_client.dart';
import '../auth/presentation/auth_controller.dart';
import 'data/mock_grades_repository.dart';
import 'data/supabase_grades_repository.dart';
import 'domain/entities.dart';
import 'domain/grades_calculator.dart';
import 'domain/grades_repository.dart';

/// En demo, singleton para que las escalas y notas registradas desde
/// admin/docente persistan durante toda la sesión (no hay backend detrás).
final gradesRepositoryProvider = Provider<GradesRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final client = ref.watch(supabaseClientProvider);
  if (client == null || auth.institution == null) {
    return MockGradesRepository();
  }
  return SupabaseGradesRepository(
    client: client,
    institutionId: auth.institution!.id,
  );
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
