import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../domain/entities.dart';
import 'money_text.dart';

class ChargeCard extends StatelessWidget {
  const ChargeCard({super.key, required this.charge, this.onTap});
  final Charge charge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (color, label) = _chipFor(charge, palette);
    final s = pastelSurface(color);
    final fmt = DateFormat("d MMM y", 'es');
    final showLateFee = charge.lateFee > 0 &&
        charge.status != ChargeStatus.paid;

    return Material(
      color: s.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration:
                    BoxDecoration(color: s.vivid, shape: BoxShape.circle),
                child: Icon(_iconFor(charge), color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      charge.conceptName,
                      style: context.textTheme.titleSmall
                          ?.copyWith(color: s.ink, fontWeight: FontWeight.w800),
                    ),
                    if (charge.description.isNotEmpty)
                      Text(
                        charge.description,
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: s.inkMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: s.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.event_outlined, size: 14, color: s.inkMuted),
              const SizedBox(width: 4),
              Text(
                charge.isOverdue && charge.status != ChargeStatus.paid
                    ? 'Vencía ${fmt.format(charge.dueDate)}'
                    : 'Vence ${fmt.format(charge.dueDate)}',
                style: context.textTheme.labelSmall?.copyWith(
                  color: charge.isOverdue ? palette.danger : s.inkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              MoneyText(
                amount: charge.pending == 0 ? charge.totalAmount : charge.pending,
                currencyCode: charge.currencyCode,
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: s.ink,
                ),
              ),
            ],
          ),
          if (showLateFee) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 14, color: palette.warning),
                const SizedBox(width: 4),
                Text(
                  'Incluye mora ${Money.format(charge.lateFee, charge.currencyCode)}',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: palette.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(Charge c) {
    if (c.conceptName.toLowerCase().contains('matrícula') ||
        c.conceptName.toLowerCase().contains('matricula')) {
      return Icons.school_outlined;
    }
    if (c.conceptName.toLowerCase().contains('mensualidad') ||
        c.conceptName.toLowerCase().contains('colegiatura')) {
      return Icons.calendar_month_outlined;
    }
    if (c.conceptName.toLowerCase().contains('uniforme')) {
      return Icons.checkroom_outlined;
    }
    if (c.conceptName.toLowerCase().contains('libro')) {
      return Icons.menu_book_outlined;
    }
    return Icons.receipt_long_outlined;
  }

  (Color, String) _chipFor(Charge c, AppPalette palette) {
    return switch (c.status) {
      ChargeStatus.paid => (palette.success, 'Pagado'),
      ChargeStatus.pending => (palette.info, 'Pendiente'),
      ChargeStatus.partial => (palette.warning, 'Parcial'),
      ChargeStatus.overdue => (palette.danger, 'Vencido'),
      ChargeStatus.cancelled => (palette.textMuted, 'Anulado'),
    };
  }
}
