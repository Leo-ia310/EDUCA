import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/animated_count.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../domain/dashboard_models.dart';

/// Carrusel horizontal compacto de materias (icono + nombre + progreso).
class SubjectsSummaryStrip extends StatelessWidget {
  const SubjectsSummaryStrip({super.key, required this.subjects, this.onTap});

  final List<SubjectProgress> subjects;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final items = subjects.take(6).toList();
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final s = items[i];
          final base = s.color ?? subjectColor(s.name);
          final p = context.pastel(base);
          final pct = (s.progress * 100).round();
          return SizedBox(
            width: 150,
            child: DepthCard(
              accent: p.vivid,
              glow: true,
              onTap: onTap,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(s.icon ?? Icons.menu_book_rounded,
                      color: p.vivid, size: 26,),
                  const Spacer(),
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(
                      value: s.progress,
                      minHeight: 5,
                      backgroundColor: p.vivid.withValues(alpha: 0.20),
                      valueColor: AlwaysStoppedAnimation(p.vivid),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('$pct%',
                      style: context.textTheme.labelSmall
                          ?.copyWith(color: context.palette.textMuted),),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Lista compacta de tareas (hasta 3) con ícono por estado.
class TasksSummary extends StatelessWidget {
  const TasksSummary({super.key, required this.tasks, this.onTap});

  final List<TaskBrief> tasks;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final items = tasks.take(3).toList();
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _TaskRow(task: items[i], onTap: onTap),
        ],
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, this.onTap});
  final TaskBrief task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (icon, color, label) = switch (task.status) {
      TaskStatus.pending => (Icons.edit_document, palette.warning, 'Pendiente'),
      TaskStatus.submitted => (Icons.upload_file_rounded, palette.info, 'Entregada'),
      TaskStatus.reviewed => (Icons.check_circle_rounded, palette.success, 'Revisada'),
      TaskStatus.late => (Icons.schedule_rounded, palette.danger, 'Atrasada'),
    };
    final s = context.pastel(color);
    return DepthCard(
      color: s.surface,
      accent: s.vivid,
      soft: true,
      onTap: onTap,
      borderRadius: Radii.md,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall
                      ?.copyWith(color: s.ink, fontWeight: FontWeight.w700),
                ),
                Text(
                  task.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(color: s.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: context.textTheme.labelSmall
                ?.copyWith(color: s.vivid, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Resumen de notas: promedio general + hasta 3 notas recientes.
class GradesSummary extends StatelessWidget {
  const GradesSummary({
    super.key,
    required this.average,
    required this.grades,
    this.onTap,
  });

  final double average;
  final List<GradeBrief> grades;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = grades.take(3).toList();
    return DepthCard(
      tilt: true,
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.pastel(const Color(0xFF9A6BE0)).surface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.grade_rounded,
                    color: Color(0xFF9A6BE0), size: 24,),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Promedio general',
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: palette.textMuted),),
                    AnimatedCount(
                      value: average,
                      decimals: 1,
                      style: context.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 16),
              _GradeRow(grade: items[i]),
            ],
          ],
        ],
      ),
    );
  }
}

class _GradeRow extends StatelessWidget {
  const _GradeRow({required this.grade});
  final GradeBrief grade;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (grade.status) {
      GradeStatus.passed => palette.success,
      GradeStatus.pending => palette.warning,
      GradeStatus.lowPerformance => palette.danger,
    };
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                grade.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                grade.activity,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall
                    ?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Text(
            grade.score.toStringAsFixed(1),
            style: context.textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
