import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/floating_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../data/mock_dashboard_data.dart';

/// Detalle de una clase del maestro. Destino del container-transform desde la
/// tarjeta de clase del dashboard.
class ClassDetailScreen extends StatelessWidget {
  const ClassDetailScreen({super.key, required this.teacherClass});
  final TeacherClass teacherClass;

  @override
  Widget build(BuildContext context) {
    final accent = subjectColor(teacherClass.name);
    final ink = subjectInk(teacherClass.name);

    return AppScaffold(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(teacherClass.name),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    child: Icon(teacherClass.icon, color: ink, size: 28),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    teacherClass.name,
                    style: context.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.meeting_room_outlined,
                          size: 16, color: context.palette.textMuted,),
                      const SizedBox(width: 6),
                      Text(teacherClass.room,
                          style: context.textTheme.bodyMedium,),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeader(title: 'Acciones'),
          const SizedBox(height: 8),
          _Action(
            icon: Icons.how_to_reg_outlined,
            label: 'Tomar asistencia',
            accent: accent,
            ink: ink,
            onTap: () => context.push(Routes.attendance),
          ),
          const SizedBox(height: 10),
          _Action(
            icon: Icons.grid_view_rounded,
            label: 'Libro de notas',
            accent: accent,
            ink: ink,
            onTap: () => context.push(Routes.gradebook),
          ),
          const SizedBox(height: 10),
          _Action(
            icon: Icons.assignment_outlined,
            label: 'Tareas y exámenes',
            accent: accent,
            ink: ink,
            onTap: () => context.push(Routes.assignments),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
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
              color: context.palette.textMuted, size: 20,),
        ],
      ),
    );
  }
}
