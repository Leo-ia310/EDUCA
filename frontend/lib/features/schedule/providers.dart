import '../portal_access/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/env.dart';
import '../../core/network/backend_api_client.dart';
import '../../core/network/provider_cache.dart';
import '../../core/network/supabase_client.dart';
import '../../core/theme/subject_palette.dart';
import '../auth/presentation/auth_controller.dart';
import '../dashboard/data/supabase_dashboard_datasource.dart'
    show iconForSubject;
import 'data/mock_schedule_repository.dart';
import '../admin/data/demo_schedules.dart';
import 'data/schedule_mock.dart';
import 'data/supabase_schedule_repository.dart';
import 'domain/schedule_repository.dart';

/// Examples are opt-in. Missing credentials/session/API never enable fixtures.
final scheduleDemoEnabledProvider = Provider<bool>((ref) => Env.forceDemo);

/// Legacy repository interface; screens use the authenticated backend below.
final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  ref.watch(portalFingerprintProvider);
  if (ref.watch(scheduleDemoEnabledProvider)) {
    return MockScheduleRepository();
  }
  final auth = ref.watch(authControllerProvider);
  final client = ref.watch(supabaseClientProvider);
  if (client == null || auth.institution == null) {
    throw StateError('No se pudo conectar con el servicio de horarios.');
  }
  return SupabaseScheduleRepository(
    client: client,
    institutionId: auth.institution!.id,
  );
});

/// Convierte los bloques que entrega el backend (o el almacén demo) al modelo
/// de la UI, agrupados por día (0 = lunes … 6 = domingo) y ordenados por hora.
Map<int, List<ClassSlot>> buildWeeklySlots(
  Iterable<Map<String, dynamic>> items,
) {
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
    queryParameters: {if (studentId != null) 'studentId': studentId},
  );
  if (data is! Map || data['schedules'] is! List) {
    throw StateError(
      'El servicio de horarios devolvió una respuesta inválida.',
    );
  }
  final items = data['schedules'] as List;
  return buildWeeklySlots([
    for (final raw in items) (raw as Map).cast<String, dynamic>(),
  ]);
}

/// Horario semanal que ve el usuario, por día (0 = lunes … 6 = domingo).
///
/// Demo explícito: el horario en memoria del módulo de horarios (parte
/// del de ejemplo, editable desde el admin). Conectado: lo que el admin
/// configuró, filtrado por el backend según el rol (clases y recesos del
/// alumno, o del maestro). Nunca se mezclan datos de ejemplo con reales.
final weeklySlotsProvider =
    FutureProvider.autoDispose<Map<int, List<ClassSlot>>>((ref) async {
  final access = ref.watch(portalAccessProvider.future);
  final demoEnabled = ref.watch(scheduleDemoEnabledProvider);
  final identity = ref.watch(
    authControllerProvider.select(
      (a) => (
        a.user?.id,
        a.user?.institutionId,
        a.user?.activeRole,
        a.institution?.id
      ),
    ),
  );
  if (demoEnabled) {
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
  if (identity.$1 == null || identity.$4 == null) {
    throw StateError('Inicia sesión para consultar tu horario.');
  }
  if (identity.$2 != identity.$4) {
    throw StateError('No se pudo validar la institución de tu horario.');
  }
  final api = ref.watch(backendApiClientProvider);
  if (api == null) {
    throw StateError('No se pudo conectar con el servicio de horarios.');
  }
  return ref.cacheAfter(
    access,
    (permissions) {
      if (!permissions.can('schedule.view')) {
        throw StateError('Tu institución restringió el acceso al horario.');
      }
      return _fetchWeekly(api);
    },
    ttl: const Duration(minutes: 5),
  );
});

/// Horario de un hijo (vista del padre). Solo conectado; en demo, el de ejemplo.
final childWeeklySlotsProvider = FutureProvider.autoDispose
    .family<Map<int, List<ClassSlot>>, int?>((ref, studentId) async {
  final access = ref.watch(portalAccessProvider.future);
  final api = ref.watch(backendApiClientProvider);
  if (ref.watch(scheduleDemoEnabledProvider)) {
    return ref.watch(weeklySlotsProvider.future);
  }
  if (studentId == null) {
    throw StateError('Selecciona un estudiante para consultar su horario.');
  }
  final identity = ref.watch(
    authControllerProvider.select(
      (a) => (
        a.user?.id,
        a.user?.institutionId,
        a.user?.activeRole,
        a.institution?.id
      ),
    ),
  );
  if (identity.$1 == null || identity.$2 != identity.$4 || api == null) {
    throw StateError('No se pudo validar la sesión para consultar el horario.');
  }
  return ref.cacheAfter(
    access,
    (permissions) {
      if (!permissions.can('schedule.view')) {
        throw StateError('Tu institución restringió el acceso al horario.');
      }
      return _fetchWeekly(api, studentId: studentId);
    },
    ttl: const Duration(minutes: 5),
  );
});
