import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

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
  CheckoutController(this._ref, this._keepPending)
      : super(const CheckoutState());
  final Ref _ref;
  final void Function() Function() _keepPending;
  void Function()? _releasePending;
  String? _idempotencyKey;
  String? _attemptChargeId;
  String? _attemptUserId;
  double? _attemptAmount;
  GatewayResult? _gatewayResult;
  String? _gatewayName;

  void setMethod(PaymentMethod m) {
    if (state.stage == CheckoutStage.processing || _gatewayResult != null) {
      return;
    }
    state = state.copyWith(method: m, clearError: true);
  }

  Future<Payment?> pay({required Charge charge}) async {
    if (state.stage == CheckoutStage.processing) return null;
    final user = _ref.read(authControllerProvider).user;
    if (user == null) {
      state = state.copyWith(errorMessage: 'Debes iniciar sesión.');
      return null;
    }

    if (state.stage == CheckoutStage.success &&
        _attemptChargeId == charge.id &&
        _attemptUserId == user.id) {
      return state.payment;
    }
    if (_attemptChargeId != charge.id || _attemptUserId != user.id) {
      _clearAttempt();
      _attemptChargeId = charge.id;
      _attemptUserId = user.id;
    }
    _idempotencyKey ??= const Uuid().v4();
    _attemptAmount ??= charge.pending;
    _releasePending ??= _keepPending();
    state = state.copyWith(stage: CheckoutStage.processing, clearError: true);
    final gateway = _ref.read(paymentGatewayProvider);
    final repo = _ref.read(paymentsRepositoryProvider);
    final method = state.method;

    try {
      final result = _gatewayResult ??
          await gateway.charge(
            amount: _attemptAmount!,
            currencyCode: charge.currencyCode,
            method: method,
            payer: PayerDetails(name: user.fullName, email: user.email),
            chargeId: charge.id,
            description: charge.conceptName,
          );

      if (!result.success) {
        _idempotencyKey = null;
        _attemptAmount = null;
        if (!mounted) return null;
        _releasePending?.call();
        _releasePending = null;
        state = state.copyWith(
          stage: CheckoutStage.failure,
          errorMessage: result.errorMessage ?? 'Pago no autorizado.',
        );
        return null;
      }
      if (!mounted) return null;
      _gatewayResult = result;
      _gatewayName ??= gateway.providerName;

      final payment = await repo.registerPayment(
        chargeId: charge.id,
        amount: _attemptAmount!,
        method: method,
        payerName: user.fullName,
        reference: result.reference,
        gatewayName: _gatewayName,
        idempotencyKey: _idempotencyKey,
      );

      if (!mounted) return payment;

      // Invalidar caches para que la UI se refresque.
      _ref.invalidate(studentBalanceProvider(charge.studentId));
      _ref.invalidate(studentChargesProvider(charge.studentId));
      _ref.invalidate(studentPaymentsProvider(charge.studentId));
      _ref.invalidate(allBalancesProvider);
      _ref.invalidate(dunningMetricsProvider);

      state = state.copyWith(stage: CheckoutStage.success, payment: payment);
      _releasePending?.call();
      _releasePending = null;
      return payment;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(
            stage: CheckoutStage.failure,
            errorMessage:
                'No se pudo confirmar el pago. Reintenta para consultar el mismo registro.',);
      }
      return null;
    }
  }

  void _clearAttempt() {
    _releasePending?.call();
    _releasePending = null;
    _idempotencyKey = null;
    _attemptChargeId = null;
    _attemptUserId = null;
    _attemptAmount = null;
    _gatewayResult = null;
    _gatewayName = null;
  }

  void reset() {
    if (state.stage == CheckoutStage.processing) return;
    // A successful gateway response awaiting registration must keep its key.
    if (_gatewayResult != null && state.stage != CheckoutStage.success) return;
    _clearAttempt();
    state = const CheckoutState();
  }
}

// Keep an unconfirmed registration across screen navigation; dispose it on
// account change so receipts and gateway references never cross sessions.
final checkoutControllerProvider = StateNotifierProvider.autoDispose
    .family<CheckoutController, CheckoutState, String>((ref, chargeId) {
  ref.watch(authControllerProvider.select((state) => state.user?.id));
  return CheckoutController(ref, () {
    final link = ref.keepAlive();
    return link.close;
  });
});
