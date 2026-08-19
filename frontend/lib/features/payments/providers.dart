import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/backend_api_client.dart';
import '../../core/network/supabase_client.dart';
import '../auth/presentation/auth_controller.dart';
import 'data/demo_payment_gateway.dart';
import 'data/mock_payments_repository.dart';
import 'data/supabase_payments_repository.dart';
import 'domain/entities.dart';
import 'domain/payment_gateway.dart';
import 'domain/payments_repository.dart';

/// En demo, singleton en memoria para que los pagos hechos durante la sesión
/// persistan entre navegaciones (no hay backend detrás).
final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final client = ref.watch(supabaseClientProvider);
  final api = ref.watch(backendApiClientProvider);
  if (client == null || api == null || auth.institution == null) {
    return MockPaymentsRepository();
  }
  return SupabasePaymentsRepository(
    client: client,
    api: api,
    institutionId: auth.institution!.id,
  );
});

/// Pasarela de pago. En producción esto sería `StripePaymentGateway(...)` o
/// similar según la config del colegio.
final paymentGatewayProvider = Provider<PaymentGateway>((ref) {
  return DemoPaymentGateway();
});

// -------------------- Read providers --------------------
final studentBalanceProvider =
    FutureProvider.autoDispose.family<StudentBalance, int>((ref, studentId) {
  return ref.watch(paymentsRepositoryProvider).balanceFor(studentId);
});

final studentChargesProvider =
    FutureProvider.autoDispose.family<List<Charge>, int>((ref, studentId) {
  return ref.watch(paymentsRepositoryProvider).chargesFor(studentId);
});

final chargeByIdProvider =
    FutureProvider.autoDispose.family<Charge?, String>((ref, id) {
  return ref.watch(paymentsRepositoryProvider).chargeById(id);
});

final studentPaymentsProvider =
    FutureProvider.autoDispose.family<List<Payment>, int>((ref, studentId) {
  return ref.watch(paymentsRepositoryProvider).paymentsFor(studentId);
});

final allBalancesProvider =
    FutureProvider.autoDispose<List<StudentBalance>>((ref) {
  return ref.watch(paymentsRepositoryProvider).allBalances();
});

final dunningMetricsProvider =
    FutureProvider.autoDispose<DunningMetrics>((ref) {
  return ref.watch(paymentsRepositoryProvider).dunningMetrics();
});
