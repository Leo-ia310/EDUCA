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
