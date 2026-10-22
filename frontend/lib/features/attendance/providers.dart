import '../auth/presentation/query_auth_provider.dart';
import '../../core/constants/env.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/backend_api_client.dart';
import '../../core/network/supabase_client.dart';
import '../../core/services/hive_init.dart';
import '../auth/presentation/auth_controller.dart';
import 'data/datasources/attendance_local_datasource.dart';
import 'data/datasources/attendance_remote_datasource.dart';
import 'data/repositories/attendance_repository_impl.dart';
import 'domain/attendance_repository.dart';

final attendanceLocalDataSourceProvider =
    Provider<AttendanceLocalDataSource>((ref) {
  final scope = ref.watch(authControllerProvider.select((auth) =>
      '${auth.institution?.id ?? 0}:${auth.user?.id ?? "signed-out"}',),);
  final local = AttendanceLocalDataSource(
    scope: Env.isDemoMode ? 'demo:$scope' : scope,
    catalog: ref.watch(attendanceCatalogBoxProvider),
    records: ref.watch(attendanceBoxProvider),
    sessions: ref.watch(classSessionBoxProvider),
    queue: ref.watch(syncQueueBoxProvider),
  );
  ref.onDispose(local.dispose);
  return local;
});

final attendanceRemoteDataSourceProvider =
    Provider<AttendanceRemoteDataSource?>((ref) {
  if (Env.isDemoMode) return null;
  final api = ref.watch(backendApiClientProvider);
  final client = ref.watch(supabaseClientProvider);
  if (api == null || client == null) return null;
  return AttendanceRemoteDataSource(api);
});

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  final auth = ref.watch(queryAuthProvider);
  return AttendanceRepositoryImpl(
    local: ref.watch(attendanceLocalDataSourceProvider),
    remote: ref.watch(attendanceRemoteDataSourceProvider),
    institutionId: auth.institution?.id ?? 0,
  );
});
