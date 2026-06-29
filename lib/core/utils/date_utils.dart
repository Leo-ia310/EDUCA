import 'package:intl/intl.dart';

class DateUtilsX {
  DateUtilsX._();

  static String greetingForHour(DateTime now) {
    final h = now.hour;
    if (h < 12) return '¡Buen día';
    if (h < 19) return '¡Buenas tardes';
    return '¡Buenas noches';
  }

  static String shortDay(DateTime d) =>
      DateFormat('EEE, d MMM', 'es').format(d);

  static String hhmm(DateTime d) => DateFormat('HH:mm', 'es').format(d);

  static String monthYear(DateTime d) => DateFormat('MMMM y', 'es').format(d);
}
