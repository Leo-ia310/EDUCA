import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../providers.dart';
import '../widgets/money_text.dart';

class AdminDunningScreen extends ConsumerWidget {
  const AdminDunningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(dunningMetricsProvider);
    final balancesAsync = ref.watch(allBalancesProvider);
    final palette = context.palette;

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Recaudación y morosidad'),
      ),
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: palette.limeDeep,
          onRefresh: () async {
            ref.invalidate(dunningMetricsProvider);
            ref.invalidate(allBalancesProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              metricsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (m) => _MetricsBlock(metrics: m),
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Estudiantes en mora'),
              const SizedBox(height: 8),
              balancesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (list) {
                  final overdue = list
                      .where((b) => b.totalOverdue > 0)
                      .toList();
                  if (overdue.isEmpty) {
                    return const EmptyState(
                      icon: Icons.verified_outlined,
                      title: '¡Sin mora!',
                      subtitle: 'Todos los estudiantes están al día.',
                    );
                  }
                  return Column(
                    children: [
                      for (final b in overdue)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: EduCard(
                            onTap: () => context.push(
                              '${Routes.payments}?studentId=${b.studentId}',
                            ),
                            child: Row(
                              children: [
                                UserAvatar(name: b.studentName, size: 40),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(b.studentName,
                                          style: context.textTheme.titleSmall
                                              ?.copyWith(
                                                  fontWeight:
                                                      FontWeight.w800)),
                                      Text(
                                        '${b.overdueCount} cargo${b.overdueCount == 1 ? '' : 's'} vencido${b.overdueCount == 1 ? '' : 's'}',
                                        style: context.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    MoneyText(
                                      amount: b.totalOverdue,
                                      currencyCode: b.currencyCode,
                                      style: context.textTheme.titleSmall
                                          ?.copyWith(
                                        color: palette.danger,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text('vencido',
                                        style: context.textTheme.labelSmall
                                            ?.copyWith(
                                                color: palette.textMuted)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricsBlock extends StatelessWidget {
  const _MetricsBlock({required this.metrics});
  final dynamic metrics;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pct = (metrics.collectionRate as double).clamp(0.0, 1.0);
    return Column(
      children: [
        EduCard(
          color: palette.cardContrast,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recaudación de este mes',
                  style: context.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    amount: metrics.collectedThisMonth as double,
                    currencyCode: metrics.currencyCode as String,
                    style: context.textTheme.displaySmall?.copyWith(
                      color: palette.lime,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '/ ${_short(metrics.expectedThisMonth as double, metrics.currencyCode as String)}',
                      style: context.textTheme.titleSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(palette.lime),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(pct * 100).toStringAsFixed(1)}% del cobro esperado',
                style: context.textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: EduCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: palette.danger, size: 18),
                    const SizedBox(height: 8),
                    MoneyText(
                      amount: metrics.totalOverdueAmount as double,
                      currencyCode: metrics.currencyCode as String,
                      style: context.textTheme.titleMedium?.copyWith(
                        color: palette.danger,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('Total vencido',
                        style: context.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: EduCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.person_off_outlined,
                        color: palette.warning, size: 18),
                    const SizedBox(height: 8),
                    Text(
                      '${metrics.overdueCount}',
                      style: context.textTheme.titleMedium?.copyWith(
                        color: palette.warning,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('Cargos en mora',
                        style: context.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _short(double v, String code) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k $code';
    return '${v.toStringAsFixed(0)} $code';
  }
}
