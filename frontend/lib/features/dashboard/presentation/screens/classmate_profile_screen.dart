import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/animated_count.dart';
import '../../../../core/widgets/charts.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../data/dashboard_data.dart';
import '../../domain/dashboard_models.dart';
import '../../providers.dart';
import '../widgets/student_chrome.dart';

/// Perfil de un compañero: sus estadísticas + comparación directa contra las
/// del alumno (gancho de engagement "compararse entre ellos").
class ClassmateProfileScreen extends ConsumerWidget {
  const ClassmateProfileScreen({super.key, required this.classmate});

  final Classmate classmate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(studentDashboardProvider).valueOrNull ??
        StudentDashboardData.mock();
    final base = subjectColor(classmate.name);
    final s = context.pastel(base);
    final firstName = classmate.name.trim().split(RegExp(r'\s+')).first;

    return StudentDetailScaffold(
      title: 'Perfil',
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado con avatar grande.
          DepthCard(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [s.vivid, Color.lerp(s.vivid, Colors.black, 0.22)!],
            ),
            borderRadius: Radii.xl,
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                _BigAvatar(name: classmate.name),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        classmate.name,
                        style: context.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        classmate.grade,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Estadísticas del compañero.
          Row(
            children: [
              Expanded(
                child: DepthCard(
                  padding: const EdgeInsets.all(14),
                  child: Center(
                    child: AttendanceRing(
                      percent: (classmate.attendanceRate * 100).round(),
                      size: 118,
                      color: s.vivid,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DepthCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.grade_rounded, color: s.vivid, size: 26),
                      const SizedBox(height: 10),
                      AnimatedCount(
                        value: classmate.average,
                        decimals: 1,
                        style: context.textTheme.displaySmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Promedio',
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: context.palette.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Comparación directa contigo.
          Text(
            'Tú vs $firstName',
            style: context.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          DepthCard(
            padding: const EdgeInsets.all(16),
            child: ComparisonBars(
              youLabel: 'Tú',
              otherLabel: firstName,
              otherColor: s.vivid,
              metrics: [
                ComparisonMetric(
                  label: 'Promedio',
                  you: me.averageScore * 10,
                  classAvg: classmate.average * 10,
                ),
                ComparisonMetric(
                  label: 'Asistencia',
                  you: me.attendanceRate * 100,
                  classAvg: classmate.attendanceRate * 100,
                ),
                ComparisonMetric(
                  label: 'Puntualidad',
                  you: 92,
                  classAvg: (classmate.attendanceRate * 100 - 4)
                      .clamp(0, 100)
                      .toDouble(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar grande circular con iniciales sobre blanco translúcido (para heros).
class _BigAvatar extends StatelessWidget {
  const _BigAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = (parts.length >= 2
            ? '${parts.first[0]}${parts[1][0]}'
            : name.isNotEmpty
                ? name[0]
                : '?')
        .toUpperCase();
    return Container(
      width: 68,
      height: 68,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
      ),
      child: Text(
        initials,
        style: context.textTheme.headlineSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
