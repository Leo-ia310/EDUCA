import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/domain/auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:educa360/features/payments/data/mock_payments_repository.dart';
import 'package:educa360/features/payments/domain/entities.dart';
import 'package:educa360/features/payments/domain/payment_gateway.dart';
import 'package:educa360/features/payments/presentation/controllers/checkout_controller.dart';
import 'package:educa360/features/payments/providers.dart';
import 'package:educa360/shared/models/app_role.dart';
import 'package:educa360/shared/models/app_user.dart';
import 'package:educa360/shared/models/institution.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends MockAuthRepository {
  @override
  Future<AuthSession?> currentSession() async => const AuthSession(
        user: AppUser(
            id: 'parent-test',
            institutionId: 1,
            email: 'parent@test.invalid',
            fullName: 'Parent Test',
            roles: [AppRole.parent],
            activeRole: AppRole.parent,),
        institution: Institution(id: 1, code: 'TEST', name: 'Test'),
      );
}

class _Gateway implements PaymentGateway {
  int calls = 0;
  @override
  String get providerName => 'test';
  @override
  Future<GatewayResult> charge(
      {required double amount,
      required String currencyCode,
      required PaymentMethod method,
      required PayerDetails payer,
      required String chargeId,
      required String description,}) async {
    calls++;
    return const GatewayResult(success: true, reference: 'gateway-test');
  }
}

class _LostResponseRepository extends MockPaymentsRepository {
  final keys = <String?>[];
  @override
  Future<Payment> registerPayment(
      {required String chargeId,
      required double amount,
      required PaymentMethod method,
      required String payerName,
      String? reference,
      String? gatewayName,
      String? idempotencyKey,}) async {
    keys.add(idempotencyKey);
    final payment = await super.registerPayment(
        chargeId: chargeId,
        amount: amount,
        method: method,
        payerName: payerName,
        reference: reference,
        gatewayName: gatewayName,
        idempotencyKey: idempotencyKey,);
    if (keys.length == 1) throw StateError('Response lost after commit');
    return payment;
  }
}

void main() {
  test(
      'lost response retries same payment after leaving checkout, without a second gateway call',
      () async {
    final repo = _LostResponseRepository(), gateway = _Gateway();
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_Auth()),
      paymentsRepositoryProvider.overrideWithValue(repo),
      paymentGatewayProvider.overrideWithValue(gateway),
    ],);
    addTearDown(container.dispose);
    container.read(authControllerProvider);
    await Future<void>.delayed(Duration.zero);
    final charge =
        (await repo.chargesFor(1001)).firstWhere((c) => c.pending > 0);
    final provider = checkoutControllerProvider(charge.id);
    final listener = container.listen(provider, (_, __) {});
    final controller = container.read(provider.notifier);
    final first = controller.pay(charge: charge);
    expect(await controller.pay(charge: charge), isNull);
    expect(await first, isNull);
    expect(container.read(provider).stage, CheckoutStage.failure);
    controller.reset(); // Must preserve the unconfirmed attempt.
    controller.setMethod(PaymentMethod.transfer);
    listener.close();
    await container.pump();
    expect(identical(container.read(provider.notifier), controller), isTrue);
    final payment = await controller.pay(charge: charge);
    expect(payment, isNotNull);
    expect(gateway.calls, 1);
    expect(repo.keys.length, 2);
    expect(repo.keys.first, isNotNull);
    expect(repo.keys[1], repo.keys[0]);
    expect((await repo.chargeById(charge.id))!.pending, 0);
    expect(await controller.pay(charge: charge), payment);
    final other =
        (await repo.chargesFor(1001)).firstWhere((c) => c.id != charge.id);
    expect(container.read(checkoutControllerProvider(other.id)).stage,
        CheckoutStage.idle,);
  });

  test(
      'demo rejects conflicting keys, overpayments and cancellation after payment',
      () async {
    final repo = MockPaymentsRepository();
    final charge =
        (await repo.chargesFor(1001)).firstWhere((c) => c.pending > 0);
    Future<Payment> pay(double amount, String key) => repo.registerPayment(
        chargeId: charge.id,
        amount: amount,
        method: PaymentMethod.cash,
        payerName: 'Parent',
        idempotencyKey: key,);
    final payment = await pay(1, 'same-key');
    expect(await pay(1, 'same-key'), payment);
    await expectLater(pay(2, 'same-key'), throwsStateError);
    await expectLater(pay(charge.pending + 1, 'new-key'), throwsStateError);
    await expectLater(repo.cancelCharge(charge.id), throwsStateError);
  });
}
