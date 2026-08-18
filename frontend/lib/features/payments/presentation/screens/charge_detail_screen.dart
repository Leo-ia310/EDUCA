import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/entities.dart';
import '../../providers.dart';
import '../widgets/money_text.dart';

class ChargeDetailScreen extends ConsumerWidget {
  const ChargeDetailScreen({super.key, required this.chargeId});
  final String chargeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chargeAsync = ref.watch(chargeByIdProvider(chargeId));
    final palette = context.palette;

    return AppScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Detalle del cargo'),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: chargeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorStateView(message: '$e'),
        data: (charge) {
          if (charge == null) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Cargo no encontrado',
            );
          }
          final canPay =
              charge.status != ChargeStatus.paid && charge.status != ChargeStatus.cancelled;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(charge: charge),
              const SizedBox(height: 16),
              const SectionHeader(title: 'Desglose'),
              const SizedBox(height: 8),
              EduCard(
                child: Column(
                  children: [
                    _KV(
                      label: 'Monto',
                      value: Money.format(charge.amount, charge.currencyCode),
                    ),
                    if (charge.discount > 0)
                      _KV(
                        label: 'Descuento',
                        value:
                            '- ${Money.format(charge.discount, charge.currencyCode)}',
                        color: palette.success,
                      ),
                    if (charge.lateFee > 0)
                      _KV(
                        label: 'Mora',
                        value:
                            '+ ${Money.format(charge.lateFee, charge.currencyCode)}',
                        color: palette.warning,
                      ),
                    if (charge.paidAmount > 0)
                      _KV(
                        label: 'Ya pagado',
                        value:
                            '- ${Money.format(charge.paidAmount, charge.currencyCode)}',
                        color: palette.info,
                      ),
                    Divider(
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.5)),
                    _KV(
                      label: charge.status == ChargeStatus.paid
                          ? 'Total pagado'
                          : 'A pagar',
                      value: Money.format(
                        charge.status == ChargeStatus.paid
                            ? charge.totalAmount
                            : charge.pending,
                        charge.currencyCode,
                      ),
                      bold: true,
                    ),
                  ],
                ),
              ),
              if (canPay) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.push(
                    '${Routes.payments}/${charge.id}/checkout',
                  ),
                  icon: const Icon(Icons.credit_card_rounded),
                  label: Text(
                    'Pagar ${Money.format(charge.pending, charge.currencyCode)}',
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.charge});
  final Charge charge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fmt = DateFormat("EEE d MMM y", 'es');
    return EduCard(
      color: charge.status == ChargeStatus.paid ? palette.lime : palette.cardContrast,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            charge.conceptName,
            style: context.textTheme.titleLarge?.copyWith(
              color: charge.status == ChargeStatus.paid
                  ? const Color(0xFF1E2218)
                  : Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            charge.description,
            style: context.textTheme.bodySmall?.copyWith(
              color: charge.status == ChargeStatus.paid
                  ? const Color(0xFF34401C)
                  : Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.person_outline,
                  size: 16,
                  color: charge.status == ChargeStatus.paid
                      ? const Color(0xFF34401C)
                      : Colors.white),
              const SizedBox(width: 4),
              Text(
                charge.studentName,
                style: TextStyle(
                  color: charge.status == ChargeStatus.paid
                      ? const Color(0xFF1E2218)
                      : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Icon(Icons.event,
                  size: 16,
                  color: charge.status == ChargeStatus.paid
                      ? const Color(0xFF34401C)
                      : Colors.white),
              const SizedBox(width: 4),
              Text(
                fmt.format(charge.dueDate),
                style: TextStyle(
                  color: charge.status == ChargeStatus.paid
                      ? const Color(0xFF1E2218)
                      : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KV extends StatelessWidget {
  const _KV({
    required this.label,
    required this.value,
    this.color,
    this.bold = false,
  });
  final String label;
  final String value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: context.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
