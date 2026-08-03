import '../domain/entities.dart';
import '../domain/payment_gateway.dart';

/// Pasarela de demo. Procesa el pago **siempre con éxito** para que la demo
/// en vivo sea 100% confiable (sin fallos aleatorios en escenario). Devuelve
/// un `reference` con formato `DEMO-<timestamp>`.
///
/// Nota: antes simulaba un 8% de fallos para probar estados de error; se
/// desactivó por seguridad de presentación. Para volver a probar el estado de
/// rechazo, poner [failAlways] en true.
class DemoPaymentGateway implements PaymentGateway {
  DemoPaymentGateway({this.failAlways = false});
  final bool failAlways;

  @override
  String get providerName => 'Educa360 Demo Gateway';

  @override
  Future<GatewayResult> charge({
    required double amount,
    required String currencyCode,
    required PaymentMethod method,
    required PayerDetails payer,
    required String chargeId,
    required String description,
  }) async {
    // Simular 3D-Secure / redirección.
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (failAlways) {
      return const GatewayResult(
        success: false,
        reference: '',
        errorMessage: 'La emisora del banco rechazó la tarjeta.',
      );
    }
    final ref = 'DEMO-${DateTime.now().millisecondsSinceEpoch}';
    return GatewayResult(
      success: true,
      reference: ref,
      rawResponse: {
        'gateway': providerName,
        'authorized_amount': amount,
        'currency': currencyCode,
        'method': method.code,
        'charge_id': chargeId,
      },
    );
  }
}
