import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/supabase_client.dart';
import '../auth/presentation/auth_controller.dart';
import '../auth/presentation/identity_providers.dart';
import 'data/dashboard_data.dart';
import 'data/supabase_dashboard_datasource.dart';

/// Datos del dashboard del estudiante. En modo conectado consulta Supabase
/// (respetando RLS); en demo usa el mock. El frontend solo lee.
final studentDashboardProvider =
    FutureProvider<StudentDashboardData>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authControllerProvider);
  if (client == null || auth.institution == null) {
    return StudentDashboardData.mock();
  }
  final studentId = await ref.watch(currentStudentIdProvider.future);
  return SupabaseDashboardDatasource(client, auth.institution!.id)
      .studentData(studentId);
});

/// Datos del dashboard del docente (clases, tareas, calificaciones recientes).
final teacherDashboardProvider =
    FutureProvider<TeacherDashboardData>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authControllerProvider);
  if (client == null || auth.institution == null) {
    return TeacherDashboardData.mock();
  }
  final teacherId = await ref.watch(currentTeacherIdProvider.future);
  if (teacherId == null) return TeacherDashboardData.empty();
  return SupabaseDashboardDatasource(client, auth.institution!.id)
      .teacherData(teacherId);
});

/// Datos del dashboard del padre/madre (hijo, asistencia, materias, actividad).
final parentDashboardProvider =
    FutureProvider<ParentDashboardData>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authControllerProvider);
  if (client == null || auth.institution == null) {
    return ParentDashboardData.mock();
  }
  final parentId = await ref.watch(currentParentIdProvider.future);
  if (parentId == null) return ParentDashboardData.empty();
  return SupabaseDashboardDatasource(client, auth.institution!.id)
      .parentData(parentId);
});

/// Datos del dashboard del administrador (a nivel institución).
final adminDashboardProvider =
    FutureProvider<AdminDashboardData>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authControllerProvider);
  if (client == null || auth.institution == null) {
    return AdminDashboardData.mock();
  }
  return SupabaseDashboardDatasource(client, auth.institution!.id).adminData();
});
