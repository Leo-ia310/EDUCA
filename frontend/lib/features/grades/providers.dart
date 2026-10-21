import '../auth/presentation/query_auth_provider.dart';
import '../portal_access/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/backend_api_client.dart';
import '../../core/network/provider_cache.dart';
import '../../core/network/supabase_client.dart';
import 'data/mock_grades_repository.dart';
import 'data/supabase_grades_repository.dart';
import 'domain/entities.dart';
import 'domain/grades_calculator.dart';
import 'domain/grades_repository.dart';

/// En demo, singleton para que las escalas y notas registradas desde
/// admin/docente persistan durante toda la sesión (no hay backend detrás).
final gradesRepositoryProvider = Provider<GradesRepository>((ref) {
  ref.watch(portalFingerprintProvider);
  final auth = ref.watch(queryAuthProvider);
  final client = ref.watch(supabaseClientProvider);
  final api = ref.watch(backendApiClientProvider);
  if (client == null || api == null || auth.institution == null) {
    return MockGradesRepository();
  }
  return SupabaseGradesRepository(
    client: client,
    api: api,
    institutionId: auth.institution!.id,
  );
});

final gradesCalculatorProvider =
    Provider<GradesCalculator>((ref) => const GradesCalculator());

/// Escalas configuradas por el colegio.
final scalesProvider = FutureProvider.autoDispose<List<GradingScale>>(
  (ref) => ref.cacheFor(
    ref.watch(gradesRepositoryProvider).scales(),
    ttl: const Duration(minutes: 5),
  ),
);

final defaultScaleProvider =
    FutureProvider.autoDispose<GradingScale>((ref) async {
  final scale = await ref.watch(gradebookScaleProvider.future);
  if (scale == null) {
    throw StateError('No hay escalas de calificación configuradas');
  }
  return scale;
});

final gradebookScaleProvider = FutureProvider.autoDispose<GradingScale?>((ref) {
  return ref.cacheFor(
    ref.watch(gradesRepositoryProvider).findDefaultScale(),
    ttl: const Duration(minutes: 5),
  );
});

final periodsProvider =
    FutureProvider.autoDispose<List<AcademicPeriod>>((ref) async {
  return ref.cacheFor(
    ref.watch(gradesRepositoryProvider).periods(),
    ttl: const Duration(minutes: 5),
  );
});

/// Periodo actualmente seleccionado en la UI. `null` = vista anual.
final selectedPeriodIdProvider = StateProvider<String?>((ref) => null);
