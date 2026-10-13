import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/env.dart';
import '../../core/network/backend_api_client.dart';
import '../../core/network/supabase_client.dart';
import '../../core/theme/subject_palette.dart';
import '../auth/presentation/auth_controller.dart';
import '../dashboard/data/supabase_dashboard_datasource.dart' show iconForSubject;
import 'data/mock_schedule_repository.dart';
import '../admin/data/demo_schedules.dart';
import 'data/schedule_mock.dart';
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

/// Convierte los bloques que entrega el backend (o el almacén demo) al modelo
/// de la UI, agrupados por día (0 = lunes … 6 = domingo) y ordenados por hora.
Map<int, List<ClassSlot>> buildWeeklySlots(Iterable<Map<String, dynamic>> items) {
  final byDay = <int, List<ClassSlot>>{};
  for (final m in items) {
    final day = (m['weekdayIndex'] as num).toInt();
    final isBreak = m['kind'] == 'break';
    final subject = '${m['subject'] ?? ''}';
    byDay.putIfAbsent(day, () => []).add(
          ClassSlot(
            start: '${m['startTime'] ?? ''}',
            end: '${m['endTime'] ?? ''}',
            subject: subject,
            room: isBreak ? '' : '${m['room'] ?? ''}',
            teacher: isBreak ? '' : '${m['teacher'] ?? ''}',
            icon: isBreak
                ? Icons.free_breakfast_rounded
                : iconForSubject(subject),
            color: isBreak ? const Color(0xFF64748B) : subjectColor(subject),
            isBreak: isBreak,
            shift: m['shift'] as String?,
          ),
        );
  }
  for (final slots in byDay.values) {
    slots.sort((a, b) => a.start.compareTo(b.start));
  }
  return byDay;
}

Future<Map<int, List<ClassSlot>>> _fetchWeekly(
  BackendApiClient api, {
  int? studentId,
}) async {
  final data = await api.get(
    '/schedules/mine',
    queryParameters: {'studentId': studentId},
  );
  final items = (data is Map ? data['schedules'] : null) as List? ?? const [];
  return buildWeeklySlots([
    for (final raw in items) (raw as Map).cast<String, dynamic>(),
  ]);
}

/// Horario semanal que ve el usuario, por día (0 = lunes … 6 = domingo).
///
/// Demo (o sin conexión): el horario en memoria del módulo de horarios (parte
/// del de ejemplo, editable desde el admin). Conectado: lo que el admin
/// configuró, filtrado por el backend según el rol (clases y recesos del
/// alumno, o del maestro). Nunca se mezclan datos de ejemplo con reales.
final weeklySlotsProvider =
    FutureProvider.autoDispose<Map<int, List<ClassSlot>>>((ref) async {
  final api = ref.watch(backendApiClientProvider);
  final user = ref.watch(authControllerProvider.select((a) => a.user));
  if (Env.isDemoMode || api == null || user == null) {
    final demo = ref.watch(demoSchedulesProvider);
    return buildWeeklySlots([
      for (final e in demo)
        {
          'weekdayIndex': e.weekdayId - 1,
          'kind': e.kind,
          'subject': e.subject,
          'startTime': e.startTime,
          'endTime': e.endTime,
          'room': e.room,
          'teacher': e.teacher,
          'shift': e.shift,
        },
    ]);
  }
  return _fetchWeekly(api);
});

/// Horario de un hijo (vista del padre). Solo conectado; en demo, el de ejemplo.
final childWeeklySlotsProvider = FutureProvider.autoDispose
    .family<Map<int, List<ClassSlot>>, int?>((ref, studentId) async {
  final api = ref.watch(backendApiClientProvider);
  if (Env.isDemoMode || api == null || studentId == null) {
    return ref.watch(weeklySlotsProvider.future);
  }
  return _fetchWeekly(api, studentId: studentId);
});
