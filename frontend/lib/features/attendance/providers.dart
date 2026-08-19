import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/backend_api_client.dart';
import '../../core/services/hive_init.dart';
import '../auth/presentation/auth_controller.dart';
import 'data/datasources/attendance_local_datasource.dart';
import 'data/datasources/attendance_remote_datasource.dart';
import 'data/repositories/attendance_repository_impl.dart';
import 'domain/attendance_repository.dart';

final attendanceLocalDataSourceProvider =
    Provider<AttendanceLocalDataSource>((ref) {
  return AttendanceLocalDataSource(
    records: ref.watch(attendanceBoxProvider),
    sessions: ref.watch(classSessionBoxProvider),
    queue: ref.watch(syncQueueBoxProvider),
  );
});

final attendanceRemoteDataSourceProvider =
    Provider<AttendanceRemoteDataSource?>((ref) {
  final api = ref.watch(backendApiClientProvider);
  if (api == null) return null;
  return AttendanceRemoteDataSource(api);
});

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  return AttendanceRepositoryImpl(
    local: ref.watch(attendanceLocalDataSourceProvider),
    remote: ref.watch(attendanceRemoteDataSourceProvider),
    institutionId: auth.institution?.id ?? 0,
  );
});
