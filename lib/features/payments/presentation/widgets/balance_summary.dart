import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../domain/entities.dart';
import 'money_text.dart';

/// Encabezado grande "Estado de cuenta" con total pendiente y CTA.
class BalanceSummary extends StatelessWidget {
  const BalanceSummary({
    super.key,
    required this.balance,
    this.onPayNext,
    this.onSeeHistory,
  });

  final StudentBalance balance;
  final VoidCallback? onPayNext;
  final VoidCallback? onSeeHistory;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isOk = balance.inGoodStanding && balance.totalPending == 0;
    final bg = isOk ? palette.lime : palette.cardContrast;
    final onBg = isOk ? const Color(0xFF1E2218) : Colors.white;
    return EduCard(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOk ? Icons.verified_rounded : Icons.receipt_long_rounded,
                color: onBg,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Estado de cuenta',
                style: context.textTheme.titleSmall?.copyWith(
                  color: onBg,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isOk ? 'Todo al día' : 'Pendiente por pagar',
            style: context.textTheme.labelSmall?.copyWith(
              color: onBg.withValues(alpha: 0.7),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          MoneyText(
            amount: balance.totalPending,
            currencyCode: balance.currencyCode,
            style: context.textTheme.displaySmall?.copyWith(
              color: onBg,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (balance.totalOverdue > 0) ...[
            const SizedBox(height: 4),
            Text(
              'De los cuales ${Money.format(balance.totalOverdue, balance.currencyCode)} están vencidos',
              style: context.textTheme.labelSmall?.copyWith(
                color: isOk ? const Color(0xFFB91C1C) : Colors.redAccent.shade100,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (balance.nextDueCharge != null) ...[
            const SizedBox(height: 12),
            _NextDue(
              charge: balance.nextDueCharge!,
              onColor: onBg,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (onPayNext != null && balance.totalPending > 0)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onPayNext,
                    icon: const Icon(Icons.credit_card_rounded),
                    label: const Text('Pagar ahora'),
                  ),
                ),
              if (onPayNext != null &&
                  balance.totalPending > 0 &&
                  onSeeHistory != null)
                const SizedBox(width: 10),
              if (onSeeHistory != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSeeHistory,
                    icon: Icon(Icons.history_rounded, color: onBg),
                    label: Text('Historial',
                        style: TextStyle(color: onBg)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: onBg.withValues(alpha: 0.3)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NextDue extends StatelessWidget {
  const _NextDue({required this.charge, required this.onColor});
  final Charge charge;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat("d 'de' MMMM", 'es');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: onColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.event, size: 16, color: onColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Próximo vencimiento',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: onColor.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${charge.conceptName} · ${fmt.format(charge.dueDate)}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: onColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          MoneyText(
            amount: charge.pending,
            currencyCode: charge.currencyCode,
            style: context.textTheme.titleSmall?.copyWith(
              color: onColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
