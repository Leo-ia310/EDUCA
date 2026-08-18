import 'entities.dart';

/// Resultado de un intento de cobro por pasarela.
class GatewayResult {
  const GatewayResult({
    required this.success,
    required this.reference,
    this.errorMessage,
    this.rawResponse,
  });

  final bool success;
  final String reference;
  final String? errorMessage;
  final Map<String, dynamic>? rawResponse;
}

/// Datos del tarjetahabiente/comprador que la pasarela necesita para
/// procesar el cobro.
class PayerDetails {
  const PayerDetails({
    required this.name,
    required this.email,
    this.documentId,
    this.phone,
  });

  final String name;
  final String email;
  final String? documentId;
  final String? phone;
}

/// Pasarela de pago abstracta. La app está desacoplada del proveedor
/// concreto (Stripe, Wompi, PayPal, BAC Credomatic, etc.) — cada
/// implementación mapea el flujo a su SDK.
abstract class PaymentGateway {
  String get providerName;

  /// Cobra al usuario. Bloquea hasta que llegue el resultado (o falle).
  /// En pasarelas con 3D-Secure, la implementación abre la pantalla nativa
  /// del proveedor y regresa cuando se completa.
  Future<GatewayResult> charge({
    required double amount,
    required String currencyCode,
    required PaymentMethod method,
    required PayerDetails payer,
    required String chargeId,
    required String description,
  });
}
