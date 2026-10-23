import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/backend_api_client.dart';

/// Asistencia real de un alumno en el mes actual: por cada día con registros,
/// si hubo alguna falta (`absent`) o todo fue asistencia/justificado.
class MonthAttendance {
  const MonthAttendance({
    required this.absentByDay,
    required this.streak,
  });

  /// Día del mes → `true` si ese día tiene alguna falta; `false` si asistió.
  /// Los días sin registro no aparecen.
  final Map<int, bool> absentByDay;

  /// Días seguidos con registro y sin faltas, hasta el último día marcado.
  final int streak;

  bool get isEmpty => absentByDay.isEmpty;
  int get absentDays => absentByDay.values.where((a) => a).length;
}

/// Lee `/family/attendance` del mes en curso. Devuelve `null` si no hay backend
/// (modo demo) o no se conoce el alumno.
final monthAttendanceProvider = FutureProvider.autoDispose
    .family<MonthAttendance?, int?>((ref, studentId) async {
  final api = ref.watch(backendApiClientProvider);
  if (api == null || studentId == null) return null;
  final now = DateTime.now();
  final fmt = DateFormat('yyyy-MM-dd');
  final res = await api.get('/family/attendance', queryParameters: {
    'studentId': studentId,
    'from': fmt.format(DateTime(now.year, now.month, 1)),
    'to': fmt.format(now),
  },);
  if (res is! Map) throw StateError('Respuesta de asistencia no válida.');
  final absentStatus = <String>{
    for (final s in (res['statuses'] as List? ?? const []))
      if (s is Map && s['countsAsAbsent'] == true) s['id'].toString(),
  };
  final byDay = <int, bool>{};
  for (final r in (res['records'] as List? ?? const [])) {
    if (r is! Map) continue;
    final date = DateTime.tryParse(r['date']?.toString() ?? '');
    if (date == null || date.month != now.month || date.year != now.year) {
      continue;
    }
    final absent = absentStatus.contains(r['statusId']?.toString());
    byDay[date.day] = (byDay[date.day] ?? false) || absent;
  }
  final days = byDay.keys.toList()..sort();
  var streak = 0;
  for (final d in days.reversed) {
    if (byDay[d] == true) break;
    streak++;
  }
  return MonthAttendance(absentByDay: byDay, streak: streak);
});
