import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../reports/providers.dart';
import '../../domain/entities.dart';
import '../../providers.dart';
import '../widgets/money_text.dart';

class PaymentHistoryScreen extends ConsumerWidget {
  const PaymentHistoryScreen({super.key, required this.studentId});
  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(studentPaymentsProvider(studentId));
    final palette = context.palette;
    final fmt = DateFormat("d MMM y, HH:mm", 'es');

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Historial de pagos'),
      ),
      child: SafeArea(
        bottom: false,
        child: payments.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateView(message: '$e'),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(
                icon: Icons.receipt_outlined,
                title: 'Sin pagos registrados',
                subtitle: 'Cuando realices un pago aparecerá aquí.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final p = list[i];
                return EduCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: palette.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.check_circle_rounded,
                                color: palette.success),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.chargeConcept,
                                    style: context.textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800)),
                                Text(
                                  '${p.method.label} · ${fmt.format(p.paidAt)}',
                                  style: context.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          MoneyText(
                            amount: p.amount,
                            currencyCode: p.currencyCode,
                            style: context.textTheme.titleMedium?.copyWith(
                              color: palette.success,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: palette.surfaceAlt,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              p.receiptNumber,
                              style: context.textTheme.labelSmall?.copyWith(
                                color: palette.textMuted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _openReceipt(context, ref, p),
                            icon: const Icon(Icons.picture_as_pdf_outlined,
                                size: 18),
                            label: const Text('Ver recibo'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _openReceipt(
      BuildContext context, WidgetRef ref, Payment payment) async {
    final repo = ref.read(paymentsRepositoryProvider);
    final charge = await repo.chargeById(payment.chargeId);
    if (charge == null) return;
    final user = ref.read(authControllerProvider).user;
    final institution = ref.read(authControllerProvider).institution;
    final pdf = ref.read(receiptPdfServiceProvider);
    final receipt = Receipt(
      payment: payment,
      charge: charge,
      institutionName: institution?.name ?? 'Colegio Educa360',
      payerName: user?.fullName ?? 'Padre/Tutor',
      gradeLevel: '4° Grado A',
      issuedAt: payment.paidAt,
    );
    await Printing.layoutPdf(
      onLayout: (_) => pdf.buildReceipt(receipt),
      name: 'Recibo_${payment.receiptNumber}.pdf',
    );
  }
}
