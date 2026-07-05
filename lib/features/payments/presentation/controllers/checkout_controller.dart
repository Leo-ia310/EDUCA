import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/auth_controller.dart';
import '../../domain/entities.dart';
import '../../domain/payment_gateway.dart';
import '../../providers.dart';

enum CheckoutStage { idle, processing, success, failure }

class CheckoutState {
  const CheckoutState({
    this.stage = CheckoutStage.idle,
    this.method = PaymentMethod.card,
    this.errorMessage,
    this.payment,
  });

  final CheckoutStage stage;
  final PaymentMethod method;
  final String? errorMessage;
  final Payment? payment;

  CheckoutState copyWith({
    CheckoutStage? stage,
    PaymentMethod? method,
    String? errorMessage,
    Payment? payment,
    bool clearError = false,
  }) {
    return CheckoutState(
      stage: stage ?? this.stage,
      method: method ?? this.method,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      payment: payment ?? this.payment,
    );
  }
}

class CheckoutController extends StateNotifier<CheckoutState> {
  CheckoutController(this._ref) : super(const CheckoutState());
  final Ref _ref;

  void setMethod(PaymentMethod m) =>
      state = state.copyWith(method: m, clearError: true);

  Future<Payment?> pay({required Charge charge}) async {
    final user = _ref.read(authControllerProvider).user;
    if (user == null) {
      state = state.copyWith(errorMessage: 'Debes iniciar sesión.');
      return null;
    }

    state = state.copyWith(stage: CheckoutStage.processing, clearError: true);
    final gateway = _ref.read(paymentGatewayProvider);
    final repo = _ref.read(paymentsRepositoryProvider);

    final result = await gateway.charge(
      amount: charge.pending,
      currencyCode: charge.currencyCode,
      method: state.method,
      payer: PayerDetails(name: user.fullName, email: user.email),
      chargeId: charge.id,
      description: charge.conceptName,
    );

    if (!result.success) {
      state = state.copyWith(
        stage: CheckoutStage.failure,
        errorMessage: result.errorMessage ?? 'Pago no autorizado.',
      );
      return null;
    }

    final payment = await repo.registerPayment(
      chargeId: charge.id,
      amount: charge.pending,
      method: state.method,
      payerName: user.fullName,
      reference: result.reference,
      gatewayName: gateway.providerName,
    );

    // Invalidar caches para que la UI se refresque.
    _ref.invalidate(studentBalanceProvider(charge.studentId));
    _ref.invalidate(studentChargesProvider(charge.studentId));
    _ref.invalidate(studentPaymentsProvider(charge.studentId));
    _ref.invalidate(allBalancesProvider);
    _ref.invalidate(dunningMetricsProvider);

    state = state.copyWith(stage: CheckoutStage.success, payment: payment);
    return payment;
  }

  void reset() => state = const CheckoutState();
}

final checkoutControllerProvider = StateNotifierProvider.autoDispose<
    CheckoutController, CheckoutState>((ref) {
  return CheckoutController(ref);
});
