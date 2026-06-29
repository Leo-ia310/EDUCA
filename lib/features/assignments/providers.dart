import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/supabase_client.dart';
import '../auth/presentation/auth_controller.dart';
import 'data/mock_assignment_repository.dart';
import 'data/supabase_assignment_repository.dart';
import 'data/supabase_file_upload_service.dart';
import 'domain/assignment_repository.dart';
import 'domain/file_upload_service.dart';

/// El repositorio se mantiene en singleton para no perder el estado mock
/// entre navegaciones (las tareas creadas en el form deben verse al
/// volver al feed).
final assignmentRepositoryProvider = Provider<AssignmentRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final client = ref.watch(supabaseClientProvider);
  if (client == null || auth.institution == null) {
    return MockAssignmentRepository();
  }
  return SupabaseAssignmentRepository(
    client: client,
    institutionId: auth.institution!.id,
  );
});

final fileUploadServiceProvider = Provider<FileUploadService>((ref) {
  final auth = ref.watch(authControllerProvider);
  final client = ref.watch(supabaseClientProvider);
  if (client == null || auth.institution == null) {
    return const DemoFileUploadService();
  }
  return SupabaseFileUploadService(
    client: client,
    institutionId: auth.institution!.id,
  );
});
