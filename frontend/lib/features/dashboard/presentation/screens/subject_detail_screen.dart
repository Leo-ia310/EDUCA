import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/floating_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/dashboard_models.dart';

/// Detalle de una materia. Destino del container-transform desde la tarjeta de
/// materia del dashboard del alumno.
class SubjectDetailScreen extends StatelessWidget {
  const SubjectDetailScreen({super.key, required this.subject});
  final SubjectProgress subject;

  @override
  Widget build(BuildContext context) {
    final accent = subject.color ?? subjectColor(subject.name);
    final ink = subject.color ?? subjectInk(subject.name);
    final pct = (subject.progress * 100).round();

    return AppScaffold(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(subject.name),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Héroe de la materia en su color.
          FloatingCard(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      subject.icon ?? Icons.book_outlined,
                      color: ink,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    subject.name,
                    style: context.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(subject.teacher, style: context.textTheme.bodyMedium),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(
                        'Progreso del curso',
                        style: context.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        '$pct%',
                        style: context.textTheme.titleMedium
                            ?.copyWith(color: ink, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: subject.progress),
                      duration: context.motion(AppMotion.slow),
                      curve: AppMotion.standard,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.5),
                        valueColor: AlwaysStoppedAnimation<Color>(ink),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),

          const SectionHeader(title: 'Docente'),
          const SizedBox(height: 8),
          EduCard(
            onTap: () => context.push(Routes.chat),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.person_outline_rounded, color: ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    subject.teacher,
                    style: context.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(Icons.chat_bubble_outline,
                    color: context.palette.textMuted, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const SectionHeader(title: 'Accesos'),
          const SizedBox(height: 8),
          _Shortcut(
            icon: Icons.assignment_outlined,
            label: 'Tareas de la materia',
            accent: accent,
            ink: ink,
            onTap: () => context.push(Routes.assignments),
          ),
          const SizedBox(height: 10),
          _Shortcut(
            icon: Icons.grade_outlined,
            label: 'Calificaciones',
            accent: accent,
            ink: ink,
            onTap: () => context.push(Routes.grades),
          ),
        ],
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.accent,
    required this.ink,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color accent;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return EduCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: ink, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: context.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              color: context.palette.textMuted, size: 20),
        ],
      ),
    );
  }
}
