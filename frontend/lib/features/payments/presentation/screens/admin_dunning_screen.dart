import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../providers.dart';
import '../widgets/money_text.dart';

class AdminDunningScreen extends ConsumerWidget {
  const AdminDunningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(dunningMetricsProvider);
    final balancesAsync = ref.watch(allBalancesProvider);
    final palette = context.palette;

    return StudentDetailScaffold(
      title: 'Recaudación y morosidad',
      scrollable: false,
      bottomNav: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: palette.accentDeep,
          onRefresh: () async {
            ref.invalidate(dunningMetricsProvider);
            ref.invalidate(allBalancesProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              metricsAsync.when(
                loading: () => const SkeletonList(items: 2),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (m) => _MetricsBlock(metrics: m),
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Estudiantes en mora'),
              const SizedBox(height: 8),
              balancesAsync.when(
                loading: () => const SkeletonList(),
                error: (e, _) => ErrorStateView(message: '$e'),
                data: (list) {
                  final overdue = list
                      .where((b) => b.totalOverdue > 0)
                      .toList();
                  if (overdue.isEmpty) {
                    return const EmptyState(
                      icon: Icons.verified_rounded,
                      title: '¡Sin mora!',
                      subtitle: 'Todos los estudiantes están al día.',
                    );
                  }
                  return Column(
                    children: [
                      for (final b in overdue)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Builder(builder: (context) {
                            final s = context.pastel(palette.danger);
                            return DepthCard(
                              color: s.surface,
                              accent: s.vivid,
                              soft: true,
                              onTap: () => context.push(
                                '${Routes.payments}?studentId=${b.studentId}',
                              ),
                              padding: const EdgeInsets.all(14),
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
                                                style: context
                                                    .textTheme.titleSmall
                                                    ?.copyWith(
                                                        color: s.ink,
                                                        fontWeight:
                                                            FontWeight.w800,),),
                                            Text(
                                              '${b.overdueCount} cargo${b.overdueCount == 1 ? '' : 's'} vencido${b.overdueCount == 1 ? '' : 's'}',
                                              style: context.textTheme.bodySmall
                                                  ?.copyWith(color: s.inkMuted),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          MoneyText(
                                            amount: b.totalOverdue,
                                            currencyCode: b.currencyCode,
                                            style: context.textTheme.titleSmall
                                                ?.copyWith(
                                              color: s.ink,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          Text('vencido',
                                              style: context
                                                  .textTheme.labelSmall
                                                  ?.copyWith(
                                                      color: s.inkMuted,),),
                                        ],
                                      ),
                                    ],
                              ),
                            );
                          },),
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
        DepthCard(
          padding: const EdgeInsets.all(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.cardContrast,
              Color.lerp(palette.cardContrast, Colors.black, 0.25)!,
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recaudación de este mes',
                  style: context.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                  ),),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    amount: metrics.collectedThisMonth as double,
                    currencyCode: metrics.currencyCode as String,
                    style: context.textTheme.displaySmall?.copyWith(
                      color: palette.accent,
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
                borderRadius: BorderRadius.circular(Radii.xs),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: pct),
                  duration: context.motion(AppMotion.slow),
                  curve: AppMotion.standard,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
                  ),
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
              child: _PastelMetric(
                color: palette.danger,
                icon: Icons.warning_amber_rounded,
                label: 'Total vencido',
                child: MoneyText(
                  amount: metrics.totalOverdueAmount as double,
                  currencyCode: metrics.currencyCode as String,
                  style: context.textTheme.titleMedium?.copyWith(
                    color: context.pastel(palette.danger).ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PastelMetric(
                color: palette.warning,
                icon: Icons.person_off_rounded,
                label: 'Cargos en mora',
                child: Text(
                  '${metrics.overdueCount}',
                  style: context.textTheme.titleMedium?.copyWith(
                    color: context.pastel(palette.warning).ink,
                    fontWeight: FontWeight.w800,
                  ),
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

/// Mini-KPI pastel (superficie tintada + ícono en círculo vívido) para las
/// métricas de morosidad, en el mismo lenguaje que los KPIs del panel.
class _PastelMetric extends StatelessWidget {
  const _PastelMetric({
    required this.color,
    required this.icon,
    required this.label,
    required this.child,
  });

  final Color color;
  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(color);
    return DepthCard(
      color: s.surface,
      accent: s.vivid,
      soft: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 10),
          child,
          Text(label,
              style: context.textTheme.bodySmall?.copyWith(color: s.inkMuted),),
        ],
      ),
    );
  }
}
