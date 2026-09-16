import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/floating_card.dart';
import '../../data/mock_dashboard_data.dart';

/// Detalle de una actividad reciente del hijo. Destino del container-transform
/// desde la tarjeta de actividad del dashboard del padre.
class ActivityDetailScreen extends StatelessWidget {
  const ActivityDetailScreen({super.key, required this.activity});
  final ParentActivity activity;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pct = (activity.progress * 100).round();

    return AppScaffold(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Atrás',
          onPressed: () => context.pop(),
        ),
        title: const Text('Actividad'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FloatingCard(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: palette.accentSoft,
                borderRadius: BorderRadius.circular(Radii.xl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5,),
                        decoration: BoxDecoration(
                          color: palette.accentDeep.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(
                          activity.tag,
                          style: context.textTheme.labelMedium?.copyWith(
                            color: palette.accentDeep,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (activity.score.isNotEmpty)
                        Text(
                          activity.score,
                          style: context.textTheme.headlineSmall?.copyWith(
                            color: palette.success,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    activity.title,
                    style: context.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(activity.timeAgo, style: context.textTheme.bodySmall),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Progreso',
                        style: context.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        '$pct%',
                        style: context.textTheme.titleMedium?.copyWith(
                          color: palette.accentDeep,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: activity.progress),
                      duration: context.motion(AppMotion.slow),
                      curve: AppMotion.standard,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.5),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(palette.accentDeep),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => context.push(Routes.assignments),
            icon: const Icon(Icons.assignment_rounded),
            label: const Text('Ver tareas del hijo'),
          ),
          const SizedBox(height: 10),
          DepthCard(
            soft: true,
            padding: const EdgeInsets.all(16),
            onTap: () => context.push(Routes.chat),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline, color: palette.accentDeep),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Contactar al docente',
                    style: context.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: palette.textMuted, size: 20,),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
