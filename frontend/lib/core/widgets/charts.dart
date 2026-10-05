import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'animated_count.dart';

/// Anillo (donut) de asistencia con el porcentaje animado al centro.
class AttendanceRing extends StatelessWidget {
  const AttendanceRing({
    super.key,
    required this.percent,
    this.size = 150,
    this.color,
    this.label = 'asistencia',
  });

  final int percent;
  final double size;
  final Color? color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.success;
    final track = c.withValues(alpha: 0.16);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: 0,
              centerSpaceRadius: size / 2 - 13,
              sections: [
                PieChartSectionData(
                  value: percent.toDouble(),
                  color: c,
                  radius: 12,
                  showTitle: false,
                ),
                PieChartSectionData(
                  value: (100 - percent).toDouble(),
                  color: track,
                  radius: 12,
                  showTitle: false,
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedCount(
                value: percent.toDouble(),
                suffix: '%',
                style: context.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                label,
                style: context.textTheme.labelSmall
                    ?.copyWith(color: context.palette.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mini gráfico de línea (tendencia) sin ejes, para incrustar en tarjetas.
class MiniTrendChart extends StatelessWidget {
  const MiniTrendChart({
    super.key,
    required this.values,
    this.color,
    this.minY = 0,
    this.maxY = 10,
    this.height = 60,
  });

  final List<double> values;
  final Color? color;
  final double minY;
  final double maxY;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.accent;
    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ];
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          minX: 0,
          maxX: (values.length - 1).toDouble(),
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: c,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c.withValues(alpha: 0.24), c.withValues(alpha: 0.0)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una métrica comparada tú-vs-clase (valores en % 0..100).
class ComparisonMetric {
  const ComparisonMetric({
    required this.label,
    required this.you,
    required this.classAvg,
  });
  final String label;
  final double you;
  final double classAvg;
}

/// Barras agrupadas comparando dos partes por métrica (el gancho de
/// estadísticas). Por defecto "Tú vs tu clase", pero acepta etiquetas propias
/// (p. ej. comparar contra un compañero) y color del comparado.
class ComparisonBars extends StatelessWidget {
  const ComparisonBars({
    super.key,
    required this.metrics,
    this.youLabel = 'Tú',
    this.otherLabel = 'Tu clase',
    this.otherColor,
  });

  final List<ComparisonMetric> metrics;
  final String youLabel;
  final String otherLabel;
  final Color? otherColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final you = palette.accent;
    final other = otherColor ?? palette.textMuted.withValues(alpha: 0.45);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 150,
          child: BarChart(
            BarChartData(
              maxY: 100,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(enabled: false),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= metrics.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          metrics[i].label,
                          style: context.textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < metrics.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 6,
                    barRods: [
                      BarChartRodData(
                        toY: metrics[i].you,
                        color: you,
                        width: 14,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                      BarChartRodData(
                        toY: metrics[i].classAvg,
                        color: other,
                        width: 14,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _LegendDot(color: you, label: youLabel),
            const SizedBox(width: 16),
            _LegendDot(color: other, label: otherLabel),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: context.textTheme.bodySmall),
      ],
    );
  }
}
