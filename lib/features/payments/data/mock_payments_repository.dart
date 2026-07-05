import 'package:uuid/uuid.dart';

import '../../assignments/data/mock_assignments_data.dart'
    show AssignmentsMockSeed;
import '../domain/entities.dart';
import '../domain/payments_repository.dart';
import 'mock_payments_data.dart';

const _uuid = Uuid();

/// Repositorio en memoria para el modo demo. Semilla:
/// - Todos los estudiantes de [AssignmentsMockSeed.studentNames] tienen su
///   set inicial de cargos y pagos.
/// - Cambios (registerPayment/cancelCharge) se aplican inmediatamente y se
///   reflejan en `balanceFor`.
class MockPaymentsRepository implements PaymentsRepository {
  MockPaymentsRepository() {
    _seed();
  }

  /// `{studentId: List<Charge>}`.
  final _charges = <int, List<Charge>>{};

  /// `{studentId: List<Payment>}`.
  final _payments = <int, List<Payment>>{};

  int _receiptCounter = 500;

  void _seed() {
    for (final entry in AssignmentsMockSeed.studentNames.entries) {
      _charges[entry.key] = PaymentsMockSeed.initialCharges(
        studentId: entry.key,
        studentName: entry.value,
      );
      _payments[entry.key] = PaymentsMockSeed.initialPayments(
        studentId: entry.key,
        studentName: entry.value,
      );
    }
  }

  // ---------- Consultas ----------
  @override
  Future<StudentBalance> balanceFor(int studentId) async {
    final list = _charges[studentId] ?? const <Charge>[];
    final overdue = list.where((c) => c.isOverdue && c.status != ChargeStatus.paid);
    final upcoming = list.where(
        (c) => c.status == ChargeStatus.pending && !c.isOverdue);
    final totalPending = list
        .where((c) => c.status != ChargeStatus.paid && c.status != ChargeStatus.cancelled)
        .fold<double>(0, (a, c) => a + c.pending);
    final totalOverdue =
        overdue.fold<double>(0, (a, c) => a + c.pending);
    final nextDue = upcoming.isEmpty
        ? null
        : upcoming.reduce((a, b) => a.dueDate.isBefore(b.dueDate) ? a : b);
    return StudentBalance(
      studentId: studentId,
      studentName: AssignmentsMockSeed.studentNames[studentId] ?? 'Estudiante',
      totalPending: totalPending,
      totalOverdue: totalOverdue,
      currencyCode: 'NIO',
      overdueCount: overdue.length,
      upcomingCount: upcoming.length,
      nextDueCharge: nextDue,
    );
  }

  @override
  Future<List<Charge>> chargesFor(int studentId) async {
    final list = (_charges[studentId] ?? const <Charge>[]).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return List.unmodifiable(list);
  }

  @override
  Future<Charge?> chargeById(String id) async {
    for (final list in _charges.values) {
      for (final c in list) {
        if (c.id == id) return c;
      }
    }
    return null;
  }

  @override
  Future<List<Payment>> paymentsFor(int studentId) async {
    final list = (_payments[studentId] ?? const <Payment>[]).toList()
      ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
    return List.unmodifiable(list);
  }

  // ---------- Escritura ----------
  @override
  Future<Payment> registerPayment({
    required String chargeId,
    required double amount,
    required PaymentMethod method,
    required String payerName,
    String? reference,
    String? gatewayName,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    // Localizar el cargo.
    int? studentId;
    Charge? charge;
    for (final entry in _charges.entries) {
      final idx = entry.value.indexWhere((c) => c.id == chargeId);
      if (idx == -1) continue;
      studentId = entry.key;
      charge = entry.value[idx];
      // Actualizar cargo.
      final newPaid = charge.paidAmount + amount;
      final newStatus = newPaid >= charge.totalAmount
          ? ChargeStatus.paid
          : ChargeStatus.partial;
      entry.value[idx] = charge.copyWith(
        paidAmount: newPaid,
        status: newStatus,
      );
      break;
    }
    if (studentId == null || charge == null) {
      throw StateError('Cargo $chargeId no encontrado');
    }
    final payment = Payment(
      id: 'pay-${_uuid.v4()}',
      uuid: _uuid.v4(),
      chargeId: chargeId,
      chargeConcept: charge.conceptName,
      studentName: charge.studentName,
      method: method,
      amount: amount,
      currencyCode: charge.currencyCode,
      status: PaymentStatus.paid,
      paidAt: DateTime.now(),
      receiptNumber: 'RC-2026-${(++_receiptCounter).toString().padLeft(6, '0')}',
      reference: reference,
      gatewayName: gatewayName,
      payerName: payerName,
    );
    _payments.putIfAbsent(studentId, () => []).add(payment);
    return payment;
  }

  @override
  Future<void> cancelCharge(String chargeId) async {
    for (final entry in _charges.entries) {
      final idx = entry.value.indexWhere((c) => c.id == chargeId);
      if (idx == -1) continue;
      entry.value[idx] = entry.value[idx].copyWith(status: ChargeStatus.cancelled);
      return;
    }
  }

  // ---------- Admin ----------
  @override
  Future<List<StudentBalance>> allBalances() async {
    final result = <StudentBalance>[];
    for (final id in _charges.keys) {
      result.add(await balanceFor(id));
    }
    result.sort((a, b) => b.totalOverdue.compareTo(a.totalOverdue));
    return result;
  }

  @override
  Future<DunningMetrics> dunningMetrics() async {
    final now = DateTime.now();
    final startMonth = DateTime(now.year, now.month, 1);
    double totalOverdue = 0;
    var overdueCount = 0;
    double collected = 0;
    double expected = 0;
    for (final list in _charges.values) {
      for (final c in list) {
        if (c.status == ChargeStatus.cancelled) continue;
        if (c.status != ChargeStatus.paid && c.isOverdue) {
          totalOverdue += c.pending;
          overdueCount++;
        }
        if (c.dueDate.isAfter(startMonth) &&
            c.dueDate.isBefore(DateTime(now.year, now.month + 1, 1))) {
          expected += c.totalAmount;
        }
      }
    }
    for (final list in _payments.values) {
      for (final p in list) {
        if (p.paidAt.isAfter(startMonth) && p.status == PaymentStatus.paid) {
          collected += p.amount;
        }
      }
    }
    return DunningMetrics(
      totalOverdueAmount: totalOverdue,
      overdueCount: overdueCount,
      collectedThisMonth: collected,
      expectedThisMonth: expected,
      currencyCode: 'NIO',
    );
  }
}
