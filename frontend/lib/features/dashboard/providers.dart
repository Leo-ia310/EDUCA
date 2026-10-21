import '../auth/presentation/query_auth_provider.dart';
import '../portal_access/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/supabase_client.dart';
import '../../core/network/provider_cache.dart';
import '../auth/presentation/identity_providers.dart';
import 'data/dashboard_data.dart';
import 'data/supabase_dashboard_datasource.dart';

/// Datos del dashboard del estudiante. En modo conectado consulta Supabase
/// (respetando RLS); en demo usa el mock. El frontend solo lee.
final studentDashboardProvider =
    FutureProvider.autoDispose<StudentDashboardData>((ref) async {
  ref.watch(portalFingerprintProvider);
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(queryAuthProvider);
  if (client == null || auth.institution == null) {
    return StudentDashboardData.mock();
  }
  final identity = ref.watch(currentStudentIdProvider.future);
  final showGrades =
      ref.watch(portalResolvedAccessProvider)?.annualGradesVisible ?? false;
  return ref.cacheAfter(identity, (studentId) async {
    if (studentId == null) return StudentDashboardData.empty();
    return SupabaseDashboardDatasource(client, auth.institution!.id)
        .studentData(
      studentId,
      showGrades: showGrades,
    );
  });
});

/// Datos del dashboard del docente (clases, tareas, calificaciones recientes).
final teacherDashboardProvider =
    FutureProvider.autoDispose<TeacherDashboardData>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(queryAuthProvider);
  if (client == null || auth.institution == null) {
    return TeacherDashboardData.mock();
  }
  final identity = ref.watch(currentTeacherIdProvider.future);
  return ref.cacheAfter(identity, (teacherId) async {
    if (teacherId == null) return TeacherDashboardData.empty();
    return SupabaseDashboardDatasource(client, auth.institution!.id)
        .teacherData(teacherId);
  });
});

/// Datos del dashboard del padre/madre (hijo, asistencia, materias, actividad).
final parentDashboardProvider =
    FutureProvider.autoDispose<ParentDashboardData>((ref) async {
  ref.watch(portalFingerprintProvider);
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(queryAuthProvider);
  if (client == null || auth.institution == null) {
    return ParentDashboardData.mock();
  }
  final identity = ref.watch(currentParentIdProvider.future);
  final showGrades =
      ref.watch(portalResolvedAccessProvider)?.annualGradesVisible ?? false;
  return ref.cacheAfter(identity, (parentId) async {
    if (parentId == null) return ParentDashboardData.empty();
    return SupabaseDashboardDatasource(client, auth.institution!.id).parentData(
      parentId,
      showGrades: showGrades,
    );
  });
});

/// Datos del dashboard del administrador (a nivel institución).
final adminDashboardProvider =
    FutureProvider.autoDispose<AdminDashboardData>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(queryAuthProvider);
  if (client == null || auth.institution == null) {
    return AdminDashboardData.mock();
  }
  return ref.cacheFor(
    SupabaseDashboardDatasource(client, auth.institution!.id).adminData(),
  );
});
