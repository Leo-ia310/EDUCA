import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/theme/subject_palette.dart';

/// Franja de 3 métricas "de un vistazo" bajo el saludo del alumno: promedio,
/// asistencia y tareas pendientes. Mismo lenguaje que el resto del panel:
/// tarjeta pastel + ícono en círculo vívido. Los números animan con count-up.
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

  static const _green = Color(0xFF34C77A);
  static const _blue = Color(0xFF4C8DF5);
  static const _amber = Color(0xFFF3993E);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.star_rounded,
            base: _green,
            value: average,
            decimals: 1,
            label: 'Promedio',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.event_available_rounded,
            base: _blue,
            value: attendanceRate * 100,
            suffix: '%',
            label: 'Asistencia',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.assignment_late_rounded,
            base: pendingTasks > 0 ? _amber : _green,
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
    required this.base,
    required this.value,
    required this.label,
    this.decimals = 0,
    this.suffix = '',
  });

  final IconData icon;
  final Color base;
  final double value;
  final String label;
  final int decimals;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final s = pastelSurface(base);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value),
            duration: context.motion(AppMotion.slow),
            curve: AppMotion.standard,
            builder: (context, v, _) => Text(
              '${v.toStringAsFixed(decimals)}$suffix',
              style: context.textTheme.titleLarge?.copyWith(
                color: s.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: s.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
