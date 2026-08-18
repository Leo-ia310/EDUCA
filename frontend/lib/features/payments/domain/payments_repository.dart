import 'entities.dart';

/// Acceso a cargos, pagos y balances.
abstract class PaymentsRepository {
  // ---------- Padre / estudiante ----------
  Future<StudentBalance> balanceFor(int studentId);
  Future<List<Charge>> chargesFor(int studentId);
  Future<Charge?> chargeById(String id);
  Future<List<Payment>> paymentsFor(int studentId);

  // ---------- Escritura ----------
  /// Registra un pago contra un cargo. Devuelve el `Payment` persistido.
  /// Si `amount == charge.pending`, el cargo pasa a `paid`; si es menor,
  /// pasa a `partial`.
  Future<Payment> registerPayment({
    required String chargeId,
    required double amount,
    required PaymentMethod method,
    required String payerName,
    String? reference,
    String? gatewayName,
  });

  Future<void> cancelCharge(String chargeId);

  // ---------- Admin ----------
  Future<List<StudentBalance>> allBalances();
  Future<DunningMetrics> dunningMetrics();
}
