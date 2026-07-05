import 'dart:math';

import '../domain/entities.dart';
import '../domain/payment_gateway.dart';

/// Pasarela de demo. Simula un procesamiento exitoso el 92% de las veces
/// para dar sensación real; el 8% falla para que la UI muestre estados de
/// error. Devuelve un `reference` con formato `DEMO-<timestamp>`.
class DemoPaymentGateway implements PaymentGateway {
  DemoPaymentGateway({int seed = 42}) : _rand = Random(seed);
  final Random _rand;

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
    final ok = _rand.nextDouble() < 0.92;
    if (!ok) {
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
