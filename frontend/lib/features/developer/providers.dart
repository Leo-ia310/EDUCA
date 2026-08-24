import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/supabase_client.dart';
import '../auth/presentation/auth_controller.dart';
import 'data/backend_developer_repository.dart';
import 'data/mock_developer_repository.dart';
import 'domain/developer_repository.dart';
import 'domain/entities.dart';

/// Repositorio del panel de desarrollador. En modo demo (o sin sesión/
/// institución) usa datos mock para que el dashboard sea navegable sin backend;
/// en modo conectado llama a las rutas REST `/api/developer/*`.
final developerRepositoryProvider = Provider<DeveloperRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authControllerProvider);
  if (client == null || auth.institution == null) {
    return MockDeveloperRepository();
  }
  return BackendDeveloperRepository(supabase: client);
});

/// `GET /api/developer/summary`
final developerSummaryProvider = FutureProvider<DevSummary>((ref) {
  return ref.watch(developerRepositoryProvider).summary();
});

/// `GET /api/developer/apis` — inventario de endpoints y su estado.
final developerApisProvider = FutureProvider<List<DevApi>>((ref) {
  return ref.watch(developerRepositoryProvider).apis();
});

/// `GET /api/developer/tasks` — todas las tareas (el filtrado por estado se
/// hace en el cliente).
final developerTasksProvider = FutureProvider<List<DevTask>>((ref) {
  return ref.watch(developerRepositoryProvider).tasks();
});

/// `GET /api/developer/feature-flags` — todos los flags (filtrado en cliente).
final developerFeatureFlagsProvider =
    FutureProvider<List<DevFeatureFlag>>((ref) {
  return ref.watch(developerRepositoryProvider).featureFlags();
});

/// `GET /api/developer/system-checks` — todos los chequeos (filtrado en cliente).
final developerSystemChecksProvider =
    FutureProvider<List<DevSystemCheck>>((ref) {
  return ref.watch(developerRepositoryProvider).systemChecks();
});

/// `GET /api/developer/modules` — módulos del dashboard.
final developerModulesProvider = FutureProvider<List<DevModule>>((ref) {
  return ref.watch(developerRepositoryProvider).modules();
});

/// `GET /api/developer/institutions` — instituciones (solo lectura).
final developerInstitutionsProvider =
    FutureProvider<List<DevInstitution>>((ref) {
  return ref.watch(developerRepositoryProvider).institutions();
});

/// `GET /api/developer/users` — usuarios con roles (solo lectura).
final developerUsersProvider = FutureProvider<List<DevUser>>((ref) {
  return ref.watch(developerRepositoryProvider).users();
});

/// `GET /api/developer/audit-events` — actividad técnica (solo lectura).
final developerAuditEventsProvider =
    FutureProvider<List<DevAuditEvent>>((ref) {
  return ref.watch(developerRepositoryProvider).auditEvents();
});
