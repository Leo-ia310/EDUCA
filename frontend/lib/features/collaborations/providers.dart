import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/env.dart';
import '../../core/network/backend_api_client.dart';
import '../auth/presentation/auth_controller.dart';

const collaborationPermissions = <String, String>{
  'class.view': 'Ver clase',
  'students.view': 'Ver estudiantes',
  'assignments.create': 'Subir y gestionar tareas',
  'assignments.review': 'Revisar entregas',
  'assignments.grade': 'Calificar tareas',
  'grades.write': 'Poner notas en el libro',
  'attendance.write': 'Registrar asistencia',
};

Set<String> normalizeClassPermissions(Iterable<String> selected) {
  final result = {'class.view', ...selected};
  if (result.contains('assignments.grade')) result.add('assignments.review');
  if (result.any((p) => [
        'assignments.review',
        'assignments.grade',
        'grades.write',
        'attendance.write',
      ].contains(p),)) {
    result.add('students.view');
  }
  return result;
}

final collaborationWorkspaceProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(authControllerProvider.select((auth) => auth.user?.id));
  final api = ref.watch(backendApiClientProvider);
  if (Env.isDemoMode) {
    return {
      'classes': <dynamic>[],
      'invitations': <dynamic>[],
      'teachers': <dynamic>[],
    };
  }
  if (api == null) {
    throw StateError('Inicia sesión para gestionar colaboradores.');
  }
  return Map<String, dynamic>.from(await api.get('/collaborations') as Map);
});

/// Unknown/loading permissions fail closed. Demo classes keep their local flow.
final classPermissionProvider =
    Provider.family<bool, (int, String)>((ref, args) {
  if (Env.isDemoMode) return true;
  final workspace = ref.watch(collaborationWorkspaceProvider).valueOrNull;
  final classes = workspace?['classes'] as List? ?? [];
  return classes.any((c) =>
      c['classId'] == args.$1 && (c['permissions'] as List).contains(args.$2),);
});
