import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../domain/entities.dart';
import '../../providers.dart';
import '../widgets/balance_summary.dart';
import '../widgets/charge_card.dart';

class ParentChargesScreen extends ConsumerWidget {
  const ParentChargesScreen({super.key, required this.studentId});
  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(studentBalanceProvider(studentId));
    final chargesAsync = ref.watch(studentChargesProvider(studentId));
    final palette = context.palette;

    return StudentDetailScaffold(
      title: 'Pagos y estado de cuenta',
      scrollable: false,
      bottomNav: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: balanceAsync.when(
          loading: () => const SkeletonList(),
          error: (e, _) => ErrorStateView(message: '$e'),
          data: (balance) => chargesAsync.when(
            loading: () => const SkeletonList(),
            error: (e, _) => ErrorStateView(message: '$e'),
            data: (charges) => RefreshIndicator(
              color: palette.accentDeep,
              onRefresh: () async {
                ref.invalidate(studentBalanceProvider(studentId));
                ref.invalidate(studentChargesProvider(studentId));
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                children: [
                  BalanceSummary(
                    balance: balance,
                    onPayNext: balance.nextDueCharge != null
                        ? () => context.push(
                              '${Routes.payments}/${balance.nextDueCharge!.id}',
                            )
                        : null,
                    onSeeHistory: () => context.push(
                      '${Routes.paymentsHistory}?studentId=$studentId',
                    ),
                  ),
                  const SizedBox(height: 20),
                  ..._buildSections(context, charges),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSections(BuildContext context, List<Charge> charges) {
    final overdue = charges.where((c) => c.isOverdue && c.status != ChargeStatus.paid).toList();
    final pending = charges
        .where((c) =>
            (c.status == ChargeStatus.pending || c.status == ChargeStatus.partial) &&
            !c.isOverdue,)
        .toList();
    final paid = charges.where((c) => c.status == ChargeStatus.paid).toList();

    List<Widget> section(String title, List<Charge> items) {
      if (items.isEmpty) return const [];
      return [
        SectionHeader(title: title),
        const SizedBox(height: 8),
        for (final c in items) ...[
          Builder(builder: (ctx) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ChargeCard(
                charge: c,
                onTap: () =>
                    ctx.push('${Routes.payments}/${c.id}'),
              ),
            );
          },),
        ],
        const SizedBox(height: 12),
      ];
    }

    return [
      if (overdue.isEmpty && pending.isEmpty && paid.isEmpty)
        const EmptyState(
          icon: Icons.receipt_long_rounded,
          title: 'Sin cargos',
          subtitle: 'No hay cargos registrados para el estudiante.',
        ),
      ...section('Vencidos', overdue),
      ...section('Por vencer', pending),
      ...section('Pagados', paid),
    ];
  }
}
