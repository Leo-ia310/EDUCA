import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/widgets/edu_card.dart';

/// Franja de 3 métricas "de un vistazo" bajo el saludo del alumno: promedio,
/// asistencia y tareas pendientes. Los números animan con un count-up sutil.
class DashboardStatStrip extends StatelessWidget {
  const DashboardStatStrip({
    super.key,
    required this.average,
    required this.attendanceRate,
    required this.pendingTasks,
  });

  final double average;

  /// 0..1
  final double attendanceRate;
  final int pendingTasks;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.star_rounded,
            accent: palette.limeDeep,
            value: average,
            decimals: 1,
            label: 'Promedio',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.event_available_rounded,
            accent: palette.success,
            value: attendanceRate * 100,
            suffix: '%',
            label: 'Asistencia',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.assignment_late_rounded,
            accent: pendingTasks > 0 ? palette.warning : palette.success,
            value: pendingTasks.toDouble(),
            label: 'Pendientes',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.accent,
    required this.value,
    required this.label,
    this.decimals = 0,
    this.suffix = '',
  });

  final IconData icon;
  final Color accent;
  final double value;
  final String label;
  final int decimals;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EduCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value),
            duration: context.motion(AppMotion.slow),
            curve: AppMotion.standard,
            builder: (context, v, _) => Text(
              '${v.toStringAsFixed(decimals)}$suffix',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: palette.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
