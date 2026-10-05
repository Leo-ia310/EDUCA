import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/open_card.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../../data/dashboard_data.dart';
import '../../domain/dashboard_models.dart';
import '../../providers.dart';
import '../widgets/student_chrome.dart';
import 'subject_detail_screen.dart';

/// Lista completa de las materias del estudiante. Destino de la flecha del
/// bloque "Todas las Materias" del dashboard del alumno.
class AllSubjectsScreen extends ConsumerWidget {
  const AllSubjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Datos reales del backend (fallback a demo mientras carga o sin backend).
    final data = ref.watch(studentDashboardProvider).valueOrNull ??
        StudentDashboardData.mock();
    final subjects = data.subjects;

    return StudentDetailScaffold(
      title: 'Todas las Materias',
      child: StaggeredEntrance(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Materias en pares (grid de 2 columnas) para reutilizar el mismo
          // formato de tarjeta que el dashboard.
          for (var i = 0; i < subjects.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _SubjectTile(subject: subjects[i])),
                const SizedBox(width: 16),
                if (i + 1 < subjects.length)
                  Expanded(child: _SubjectTile(subject: subjects[i + 1]))
                else
                  const Expanded(child: SizedBox()),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SubjectTile extends StatelessWidget {
  const _SubjectTile({required this.subject});
  final SubjectProgress subject;

  @override
  Widget build(BuildContext context) {
    return OpenCard(
      closed: (context, open) => _FolderCard(subject: subject, onTap: open),
      open: (context) => SubjectDetailScreen(subject: subject),
    );
  }
}

/// Tarjeta tipo carpeta (neo-brutalista): pestaña de color, borde negro grueso
/// y sombra dura. Ícono en cuadro tintado, docente arriba y nombre abajo.
class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.subject, required this.onTap});
  final SubjectProgress subject;
  final VoidCallback onTap;

  static const _border = 2.0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : Colors.black;
    final s = context.pastel(subject.color ?? subjectColor(subject.name));
    final tabColor = dark ? s.vivid : s.vivid.withValues(alpha: 0.55);
    final iconBg = dark ? s.surface : s.vivid.withValues(alpha: 0.28);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 164,
        child: Stack(
          children: [
            // Pestaña de la carpeta.
            Positioned(
              left: 4,
              top: 0,
              child: Container(
                width: 64,
                height: 22,
                decoration: BoxDecoration(
                  color: tabColor,
                  border: Border.all(color: ink, width: _border),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              top: 12,
              right: 5,
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.palette.cardElevated,
                  border: Border.all(color: ink, width: _border),
                  borderRadius: BorderRadius.circular(Radii.md),
                  boxShadow: [
                    BoxShadow(color: ink, offset: const Offset(5, 5)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: iconBg,
                            border: Border.all(color: ink, width: _border),
                            borderRadius: BorderRadius.circular(Radii.sm),
                          ),
                          child: Icon(
                            subject.icon ?? Icons.menu_book_rounded,
                            color: ink,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            subject.teacher,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.labelSmall?.copyWith(
                              color: context.palette.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            subject.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: iconBg,
                            border: Border.all(color: ink, width: _border),
                            borderRadius: BorderRadius.circular(Radii.xs + 4),
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: ink,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
