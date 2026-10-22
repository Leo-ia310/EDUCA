import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Formatter reutilizable de moneda. Usa `NIO` como default; el símbolo se
/// elige por [currencyCode].
class Money {
  Money._();

  static String format(double amount, String currencyCode) {
    final symbol = _symbolFor(currencyCode);
    final formatter = NumberFormat.currency(
      locale: 'es',
      symbol: symbol,
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  /// Monto abreviado («35.7k») con el mismo símbolo que [format].
  static String compact(double amount, String currencyCode) {
    final symbol = _symbolFor(currencyCode).trim();
    final body = amount >= 1000
        ? '${(amount / 1000).toStringAsFixed(1)}k'
        : amount.toStringAsFixed(0);
    return '$symbol $body';
  }

  static String _symbolFor(String code) {
    return switch (code.toUpperCase()) {
      'NIO' => 'C\$ ',
      'USD' => 'US\$ ',
      'EUR' => '€ ',
      'CRC' => '₡ ',
      _ => '$code ',
    };
  }
}

class MoneyText extends StatelessWidget {
  const MoneyText(
      {super.key, required this.amount, required this.currencyCode, this.style,});
  final double amount;
  final String currencyCode;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(Money.format(amount, currencyCode), style: style);
  }
}
