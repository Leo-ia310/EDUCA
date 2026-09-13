import 'package:flutter_test/flutter_test.dart';

import 'package:educa360/features/payments/domain/entities.dart';

Charge _charge({
  double amount = 1000,
  double discount = 0,
  double lateFee = 0,
  double paidAmount = 0,
  DateTime? dueDate,
  ChargeStatus status = ChargeStatus.pending,
}) =>
    Charge(
      id: 'c1',
      studentId: 1,
      studentName: 'Ana',
      conceptId: 'mensualidad',
      conceptName: 'Mensualidad',
      description: '',
      amount: amount,
      discount: discount,
      lateFee: lateFee,
      paidAmount: paidAmount,
      dueDate: dueDate ?? DateTime(2999, 1, 1),
      currencyCode: 'NIO',
      status: status,
      academicYear: '2026',
    );

void main() {
  group('Charge.totalAmount', () {
    test('resta descuento y suma mora', () {
      expect(_charge(amount: 1000, discount: 100, lateFee: 50).totalAmount, 950);
    });
  });

  group('Charge.pending', () {
    test('es el total menos lo pagado', () {
      expect(_charge(amount: 1000, paidAmount: 400).pending, 600);
    });

    test('nunca es negativo aunque se pague de más', () {
      expect(_charge(amount: 1000, paidAmount: 1200).pending, 0);
    });
  });

  group('Charge.isOverdue', () {
    final past = DateTime(2020, 1, 1);
    final future = DateTime(2999, 1, 1);

    test('vencido: pasada la fecha y sin pagar', () {
      expect(_charge(dueDate: past, status: ChargeStatus.pending).isOverdue,
          isTrue);
    });

    test('no vencido si ya está pagado, aunque haya pasado la fecha', () {
      expect(
          _charge(dueDate: past, status: ChargeStatus.paid).isOverdue, isFalse);
    });

    test('no vencido si la fecha aún no llega', () {
      expect(_charge(dueDate: future, status: ChargeStatus.pending).isOverdue,
          isFalse);
    });
  });
}
