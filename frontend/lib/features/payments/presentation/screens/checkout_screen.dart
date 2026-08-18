import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/entities.dart';
import '../../providers.dart';
import '../controllers/checkout_controller.dart';
import '../widgets/money_text.dart';

class CheckoutScreen extends ConsumerWidget {
  const CheckoutScreen({super.key, required this.chargeId});
  final String chargeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chargeAsync = ref.watch(chargeByIdProvider(chargeId));

    return AppScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Pagar cargo'),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: chargeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorStateView(message: '$e'),
        data: (charge) {
          if (charge == null) return const Center(child: Text('Cargo no encontrado'));
          return _CheckoutBody(charge: charge);
        },
      ),
    );
  }
}

class _CheckoutBody extends ConsumerWidget {
  const _CheckoutBody({required this.charge});
  final Charge charge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(checkoutControllerProvider);
    final ctrl = ref.read(checkoutControllerProvider.notifier);
    final palette = context.palette;

    if (state.stage == CheckoutStage.success && state.payment != null) {
      return _SuccessView(payment: state.payment!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EduCard(
          color: palette.limeSoft,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(charge.conceptName,
                        style: context.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: palette.limeDeep)),
                    Text(charge.description,
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: palette.limeDeep)),
                  ],
                ),
              ),
              MoneyText(
                amount: charge.pending,
                currencyCode: charge.currencyCode,
                style: context.textTheme.titleLarge?.copyWith(
                    color: palette.limeDeep,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Método de pago'),
        const SizedBox(height: 8),
        for (final method in PaymentMethod.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MethodTile(
              method: method,
              selected: state.method == method,
              onTap: () => ctrl.setMethod(method),
            ),
          ),
        const SizedBox(height: 12),
        if (state.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(state.errorMessage!,
                style: TextStyle(color: palette.danger)),
          ),
        FilledButton.icon(
          onPressed: state.stage == CheckoutStage.processing
              ? null
              : () => ctrl.pay(charge: charge),
          icon: state.stage == CheckoutStage.processing
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lock_rounded),
          label: Text(state.stage == CheckoutStage.processing
              ? 'Procesando…'
              : 'Confirmar pago'),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Pago protegido — Educa360 Demo Gateway',
            style: context.textTheme.labelSmall
                ?.copyWith(color: palette.textMuted),
          ),
        ),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? palette.limeSoft : palette.cardElevated,
          border: Border.all(
            color: selected
                ? palette.limeDeep
                : Theme.of(context).dividerColor,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (selected ? palette.limeDeep : palette.textMuted)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_iconFor(method),
                  color: selected ? palette.limeDeep : palette.textMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(method.label,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    _descFor(method),
                    style: context.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? palette.limeDeep : palette.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(PaymentMethod m) => switch (m) {
        PaymentMethod.card => Icons.credit_card_rounded,
        PaymentMethod.transfer => Icons.account_balance_rounded,
        PaymentMethod.cash => Icons.payments_rounded,
        PaymentMethod.wallet => Icons.account_balance_wallet_rounded,
      };

  String _descFor(PaymentMethod m) => switch (m) {
        PaymentMethod.card => 'Débito o crédito, incluye 3D-Secure',
        PaymentMethod.transfer => 'Transferencia bancaria (SPBT/ACH)',
        PaymentMethod.cash => 'Registrar pago hecho en caja',
        PaymentMethod.wallet => 'Tigo Money, Kash, Pago Móvil',
      };
}

class _SuccessView extends ConsumerWidget {
  const _SuccessView({required this.payment});
  final Payment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.success.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_rounded,
                  color: palette.success, size: 54),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text('¡Pago confirmado!',
                style: context.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Recibo ${payment.receiptNumber}',
              style: context.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 20),
          EduCard(
            child: Column(
              children: [
                _Kv(label: 'Concepto', value: payment.chargeConcept),
                _Kv(
                  label: 'Monto',
                  value: Money.format(payment.amount, payment.currencyCode),
                ),
                _Kv(label: 'Método', value: payment.method.label),
                if (payment.reference != null)
                  _Kv(label: 'Referencia', value: payment.reference!),
                if (payment.gatewayName != null)
                  _Kv(label: 'Procesador', value: payment.gatewayName!),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => context.push(
              '${Routes.paymentsReceipt}?paymentId=${payment.id}&studentId=${payment.studentName}',
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Ver recibo en PDF'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => context.pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.textTheme.bodySmall)),
          Text(value,
              style: context.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
