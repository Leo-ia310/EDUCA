import 'package:intl/intl.dart';

class DateUtilsX {
  DateUtilsX._();

  /// Saludo según la hora del día. Fuente única para el hero de todos los
  /// paneles (alumno, docente, padre, admin).
  static String greetingForHour(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  static String shortDay(DateTime d) =>
      DateFormat('EEE, d MMM', 'es').format(d);

  static String hhmm(DateTime d) => DateFormat('HH:mm', 'es').format(d);

  static String monthYear(DateTime d) => DateFormat('MMMM y', 'es').format(d);

  /// Convierte "HH:MM" en minutos desde medianoche (tolerante a formatos
  /// incompletos o inválidos).
  static int hhmmToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return h * 60 + m;
  }
}
