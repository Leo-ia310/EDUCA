import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/backend_api_client.dart';
import '../../core/network/supabase_client.dart';
import '../attendance/data/mock_attendance_data.dart';
import '../attendance/domain/entities.dart';
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
  final api = ref.watch(backendApiClientProvider);
  if (client == null || api == null || auth.institution == null) {
    return MockAssignmentRepository();
  }
  return SupabaseAssignmentRepository(
    client: client,
    api: api,
    institutionId: auth.institution!.id,
  );
});

/// Clases disponibles para el selector del formulario de tareas.
///
/// En modo conectado consulta las clases REALES de la institución en Supabase
/// (IDs `bigint` válidos → evita el error FK/22P02 al crear tareas). En modo
/// demo devuelve las clases mock. Nunca hardcodea IDs en la UI.
final teacherClassesProvider =
    FutureProvider<List<ClassSessionBrief>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  final api = ref.watch(backendApiClientProvider);
  if (api == null || auth.institution == null) {
    return AttendanceMock.todaysClasses;
  }
  final rows = await api.call('assignments.teacherClasses') as List;
  return rows.map((r) {
    final m = Map<String, dynamic>.from(r as Map);
    return ClassSessionBrief(
      classId: (m['classId'] as num).toInt(),
      groupId: (m['groupId'] as num?)?.toInt() ?? 0,
      subjectName: m['subjectName'] as String? ?? 'Materia',
      groupName: m['groupName'] as String? ?? 'Grupo',
      startTime: m['startTime'] as String? ?? '',
      endTime: m['endTime'] as String? ?? '',
      studentCount: (m['studentCount'] as num?)?.toInt() ?? 0,
    );
  }).toList();
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
