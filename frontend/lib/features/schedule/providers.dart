import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/supabase_client.dart';
import '../auth/presentation/auth_controller.dart';
import 'data/mock_schedule_repository.dart';
import 'data/supabase_schedule_repository.dart';
import 'domain/schedule_repository.dart';

/// Listo para cuando `ScheduleScreen` se cablee a datos reales — ver el
/// comentario en `domain/schedule_repository.dart`. Hoy nada consume este
/// provider todavía.
final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final client = ref.watch(supabaseClientProvider);
  if (client == null || auth.institution == null) {
    return MockScheduleRepository();
  }
  return SupabaseScheduleRepository(
    client: client,
    institutionId: auth.institution!.id,
  );
});
