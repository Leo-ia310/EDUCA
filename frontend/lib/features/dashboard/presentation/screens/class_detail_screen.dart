import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../collaborations/class_students_screen.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/floating_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../data/mock_dashboard_data.dart';
import '../widgets/student_chrome.dart';

/// Detalle de una clase del maestro. Destino del container-transform desde la
/// tarjeta de clase del dashboard.
class ClassDetailScreen extends StatelessWidget {
  const ClassDetailScreen({super.key, required this.teacherClass});
  final TeacherClass teacherClass;

  @override
  Widget build(BuildContext context) {
    final accent = subjectColor(teacherClass.name);
    final ink = subjectInk(teacherClass.name);

    return StudentDetailScaffold(
      title: teacherClass.name,
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FloatingCard(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(Radii.xl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Icon(teacherClass.icon, color: ink, size: 28),
                  ),
                  const SizedBox(height: 14),
                  Text(
                      teacherClass.isOwner
                          ? 'Clase propia'
                          : 'Clase colaborativa',
                      style: context.textTheme.labelLarge,),
                  Text(
                    teacherClass.name,
                    style: context.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.meeting_room_rounded,
                        size: 16,
                        color: context.palette.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        teacherClass.room,
                        style: context.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (teacherClass.isOwner) ...[
            _Action(
                icon: Icons.group_add_rounded,
                label: 'Invitar profesor colaborador',
                accent: accent,
                ink: ink,
                onTap: () => context.push(Routes.collaborations),),
            const SizedBox(height: 12),
          ],
          const SectionHeader(title: 'Acciones'),
          if (teacherClass.can('students.view') && teacherClass.classId != null)
            _Action(icon: Icons.groups_rounded, label: 'Ver estudiantes', accent: accent, ink: ink,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ClassStudentsScreen(classId: teacherClass.classId!))),),
          const SizedBox(height: 8),
          if (teacherClass.can('attendance.write'))
            _Action(
              icon: Icons.how_to_reg_rounded,
              label: 'Tomar asistencia',
              accent: accent,
              ink: ink,
              onTap: () => context.push(Routes.attendance),
            ),
          const SizedBox(height: 10),
          if (teacherClass.can('students.view'))
            _Action(
              icon: Icons.grid_view_rounded,
              label: 'Libro de notas',
              accent: accent,
              ink: ink,
              onTap: () => context.push(Routes.gradebook),
            ),
          const SizedBox(height: 10),
          _Action(
            icon: Icons.assignment_rounded,
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
    return DepthCard(
      soft: true,
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(Radii.sm),
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
          Icon(
            Icons.chevron_right_rounded,
            color: context.palette.textMuted,
            size: 20,
          ),
        ],
      ),
    );
  }
}
