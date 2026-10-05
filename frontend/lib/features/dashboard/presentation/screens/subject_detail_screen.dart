import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../assignments/domain/entities.dart';
import '../../../assignments/presentation/controllers/assignments_list_controller.dart';
import '../../../assignments/presentation/widgets/assignment_card.dart';
import '../../domain/dashboard_models.dart';
import '../../providers.dart';
import '../widgets/student_chrome.dart';

/// Detalle de una materia. Destino del container-transform desde la tarjeta de
/// materia del dashboard del alumno. Estilo panel: hero con degradado en el
/// color de la materia (ícono de fondo) + secciones de Docente, Tareas y
/// Calificaciones propias de la materia.
class SubjectDetailScreen extends ConsumerWidget {
  const SubjectDetailScreen({super.key, required this.subject});
  final SubjectProgress subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.pastel(subject.color ?? subjectColor(subject.name));

    final assignmentsAsync = ref.watch(studentAssignmentsProvider);
    final tasks = assignmentsAsync.valueOrNull
            ?.where((a) =>
                a.subjectName == subject.name &&
                a.kind != AssignmentKind.exam &&
                a.kind != AssignmentKind.quiz,)
            .toList() ??
        const <Assignment>[];

    final data = ref.watch(studentDashboardProvider).valueOrNull;
    final subjectGrades =
        data?.grades.where((g) => g.subject == subject.name).toList() ??
            const <GradeBrief>[];
    final avg = subjectGrades.isEmpty
        ? null
        : subjectGrades.map((g) => g.score).reduce((a, b) => a + b) /
            subjectGrades.length;

    return StudentDetailScaffold(
      title: subject.name,
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero de la materia: ícono grande de fondo + nombre/profesor arriba.
          Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.only(right: 4, bottom: 4),
            decoration: Brutal.decoration(
              context,
              color: s.vivid,
              radius: Radii.lg,
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -20,
                  bottom: -20,
                  child: Icon(
                    subject.icon ?? Icons.menu_book_rounded,
                    size: 128,
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject.name,
                        style: context.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subject.teacher,
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

          SectionHeader(
            title: 'Tareas',
            action: 'Ver todas',
            onActionTap: () => context.push(Routes.assignments),
          ),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            const EmptyState(
              icon: Icons.task_alt_rounded,
              title: 'Sin tareas',
              subtitle: 'No hay tareas asignadas en esta materia por ahora.',
            )
          else
            for (final a in tasks) ...[
              AssignmentCard(
                assignment: a,
                pastel: true,
                showProgress: false,
                onTap: () => context.push('${Routes.assignments}/${a.id}'),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 12),

          const SectionHeader(title: 'Calificaciones'),
          const SizedBox(height: 8),
          DepthCard(brutal: true, 
            color: s.surface,
            accent: s.vivid,
            soft: true,
            borderRadius: Radii.md,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  avg == null ? '—' : avg.toStringAsFixed(1),
                  style: context.textTheme.headlineSmall
                      ?.copyWith(color: s.ink, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Promedio de la materia',
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: s.inkMuted),
                  ),
                ),
              ],
            ),
          ),
          if (subjectGrades.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final g in subjectGrades) ...[
              _GradeRow(surface: s, grade: g),
              const SizedBox(height: 8),
            ],
          ],
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
    return DepthCard(brutal: true, 
      color: surface.surface,
      accent: surface.vivid,
      soft: true,
      onTap: onTap,
      borderRadius: Radii.md,
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
    );
  }
}

/// Fila de una calificación anterior (tarea o prueba) de la materia.
class _GradeRow extends StatelessWidget {
  const _GradeRow({required this.surface, required this.grade});
  final PastelSurface surface;
  final GradeBrief grade;

  @override
  Widget build(BuildContext context) {
    return DepthCard(brutal: true, 
      color: surface.surface,
      soft: true,
      borderRadius: Radii.md,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              grade.activity,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: surface.ink, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            grade.score.toStringAsFixed(1),
            style: context.textTheme.titleSmall?.copyWith(
              color: surface.vivid,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
