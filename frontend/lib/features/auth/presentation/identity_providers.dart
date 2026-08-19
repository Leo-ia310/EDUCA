import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_client.dart';
import 'auth_controller.dart';

/// Identidad operativa del usuario logueado, resuelta EN EL BACKEND.
///
/// El frontend no hardcodea IDs: llama a las funciones RPC
/// `current_student_id` / `current_teacher_id` / `my_children_student_ids`
/// (ver `supabase/migrations/0009_demo_linkage_and_chat.sql`), que
/// mapean `auth.uid()` → entidad vía `users.person_id`.
///
/// En modo demo (sin cliente Supabase) devuelven los IDs del seed mock para
/// que el shell visual siga funcionando sin backend.

const _demoStudentId = 1001;

int? _asInt(dynamic v) => v is num ? v.toInt() : null;

/// student_id del usuario logueado (rol student).
final currentStudentIdProvider = FutureProvider<int>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authControllerProvider);
  if (client == null || auth.institution == null) return _demoStudentId;
  final res = await client.rpc('current_student_id');
  return _asInt(res) ?? _demoStudentId;
});

/// teacher_id del usuario logueado (rol teacher). `null` si no aplica.
final currentTeacherIdProvider = FutureProvider<int?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authControllerProvider);
  if (client == null || auth.institution == null) return null;
  final res = await client.rpc('current_teacher_id');
  return _asInt(res);
});

/// parent_id del usuario logueado (rol parent). `null` si no aplica.
final currentParentIdProvider = FutureProvider<int?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authControllerProvider);
  if (client == null || auth.institution == null) return null;
  final res = await client.rpc('current_parent_id');
  return _asInt(res);
});

/// student_id del primer hijo del usuario logueado (rol parent).
final parentChildStudentIdProvider = FutureProvider<int>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authControllerProvider);
  if (client == null || auth.institution == null) return _demoStudentId;
  final res = await client.rpc('my_children_student_ids');
  if (res is List && res.isNotEmpty) {
    return _asInt(res.first) ?? _demoStudentId;
  }
  return _demoStudentId;
});
