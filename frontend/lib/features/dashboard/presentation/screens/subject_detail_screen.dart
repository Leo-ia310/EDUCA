import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/dashboard_models.dart';

/// Detalle de una materia. Destino del container-transform desde la tarjeta de
/// materia del dashboard del alumno. Estilo panel: hero con degradado en el
/// color de la materia + filas pastel con círculo vívido.
class SubjectDetailScreen extends StatelessWidget {
  const SubjectDetailScreen({super.key, required this.subject});
  final SubjectProgress subject;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subject.color ?? subjectColor(subject.name));
    final deep = Color.lerp(s.vivid, Colors.black, 0.18)!;
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
          // Hero de la materia con degradado en su color.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [s.vivid, deep],
              ),
              borderRadius: BorderRadius.circular(Radii.xl),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    subject.icon ?? Icons.menu_book_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  subject.name,
                  style: context.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subject.teacher,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      'Progreso del curso',
                      style: context.textTheme.labelMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$pct%',
                      style: context.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: subject.progress),
                    duration: context.motion(AppMotion.slow),
                    curve: AppMotion.standard,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.28),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          const SectionHeader(title: 'Docente'),
          const SizedBox(height: 8),
          _PastelRow(
            surface: s,
            icon: Icons.person_outline_rounded,
            label: subject.teacher,
            trailing: Icons.chat_bubble_outline,
            onTap: () => context.push(Routes.chat),
          ),
          const SizedBox(height: 20),

          const SectionHeader(title: 'Accesos'),
          const SizedBox(height: 8),
          _PastelRow(
            surface: s,
            icon: Icons.assignment_outlined,
            label: 'Tareas de la materia',
            onTap: () => context.push(Routes.assignments),
          ),
          const SizedBox(height: 10),
          _PastelRow(
            surface: s,
            icon: Icons.grade_outlined,
            label: 'Calificaciones',
            onTap: () => context.push(Routes.grades),
          ),
        ],
      ),
    );
  }
}

class _PastelRow extends StatelessWidget {
  const _PastelRow({
    required this.surface,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing = Icons.chevron_right_rounded,
  });

  final PastelSurface surface;
  final IconData icon;
  final String label;
  final IconData trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Ink(
          decoration: BoxDecoration(
            color: surface.surface,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: surface.vivid,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleSmall?.copyWith(
                      color: surface.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(trailing, color: surface.inkMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
