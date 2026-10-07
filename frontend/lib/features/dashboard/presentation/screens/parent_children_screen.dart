import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../../data/dashboard_data.dart';
import '../../data/mock_dashboard_data.dart';
import '../../providers.dart';
import '../widgets/home_tile_card.dart';
import '../widgets/student_chrome.dart';
import 'student_attendance_screen.dart';

/// Hijo seleccionado en el panel "Mis hijos" (índice en la lista).
final selectedChildIndexProvider = StateProvider<int>((ref) => 0);

const _childColors = [Color(0xFF4C8DF5), Color(0xFFF3993E), Color(0xFF9A6BE0)];

/// Panel "Mis hijos": carrusel de tarjetas (una por hijo), promedio de
/// asistencia del hijo seleccionado y accesos a sus Tareas y Exámenes.
class ParentChildrenScreen extends ConsumerStatefulWidget {
  const ParentChildrenScreen({super.key});

  @override
  ConsumerState<ParentChildrenScreen> createState() =>
      _ParentChildrenScreenState();
}

class _ParentChildrenScreenState extends ConsumerState<ParentChildrenScreen> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      viewportFraction: 0.84,
      initialPage: ref.read(selectedChildIndexProvider),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int to) => _controller.animateToPage(
        to,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(parentDashboardProvider).valueOrNull ??
        ParentDashboardData.mock();
    final kids = data.children;
    final selected =
        ref.watch(selectedChildIndexProvider).clamp(0, kids.length - 1);
    final child = kids[selected];

    return StudentDetailScaffold(
      title: 'Mis hijos',
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Mis hijos', accent: false),
          const SizedBox(height: 12),
          // Un solo hijo: la tarjeta queda centrada (padEnds).
          SizedBox(
            height: 210,
            child: Stack(
              children: [
                Positioned.fill(
                  child: PageView.builder(
                    controller: _controller,
                    // Solo se cambia de hijo con las flechas.
                    physics: const NeverScrollableScrollPhysics(),
                    padEnds: true,
                    itemCount: kids.length,
                    onPageChanged: (i) =>
                        ref.read(selectedChildIndexProvider.notifier).state = i,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _ChildCard(
                        child: kids[i],
                        color: _childColors[i % _childColors.length],
                        selected: i == selected,
                      ),
                    ),
                  ),
                ),
                if (kids.length > 1) ...[
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: _ArrowButton(
                      icon: Icons.chevron_left_rounded,
                      enabled: selected > 0,
                      onTap: () => _go(selected - 1),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: _ArrowButton(
                      icon: Icons.chevron_right_rounded,
                      enabled: selected < kids.length - 1,
                      onTap: () => _go(selected + 1),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (kids.length > 1) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < kids.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == selected ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == selected
                          ? context.palette.accentDeep
                          : context.palette.textMuted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          // Al cambiar de hijo, las secciones se reconstruyen con animación.
          StaggeredEntrance(
            key: ValueKey(selected),
            children: [
              const SectionHeader(
                  title: 'Promedio de asistencias', accent: false,),
              const SizedBox(height: 12),
              HomeOptionCard(
                icon: Icons.event_available_rounded,
                title: 'Promedio de asistencias',
                subtitle:
                    '${(child.attendance ?? data.attendancePercent).round()}% · ${child.name}',
                color: const Color(0xFF2FA869),
                art: const ArtCluster([
                  ArtItem.icon(
                    Icons.check_circle_rounded,
                    size: 64,
                    top: 4,
                    right: 40,
                    angle: 0.2,
                  ),
                  ArtItem.icon(
                    Icons.calendar_month_rounded,
                    size: 48,
                    top: 50,
                    right: 0,
                    angle: -0.3,
                  ),
                ]),
                onTap: () => context.push(Routes.parentAttendance),
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Docentes por materia', accent: false),
          const SizedBox(height: 12),
          HomeOptionCard(
            icon: Icons.menu_book_rounded,
            title: 'Maestros',
            subtitle: 'Maestros y materias',
            color: const Color(0xFF9A6BE0),
            art: const ArtCluster([
              ArtItem.icon(Icons.school_rounded,
                  size: 64, top: 4, right: 40, angle: 0.25,),
              ArtItem.icon(Icons.edit_note_rounded,
                  size: 48, top: 50, right: 0, angle: -0.3,),
            ]),
            onTap: () => context.push(Routes.parentTeachers),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Tareas y Exámenes', accent: false),
              const SizedBox(height: 12),
              HomeOptionCard(
                icon: Icons.note_alt_rounded,
                title: 'Tareas',
                subtitle: 'Pendientes y entregadas de ${child.name}',
                color: const Color(0xFFF3993E),
                art: const ArtCluster([
                  ArtItem.icon(
                    Icons.edit_rounded,
                    size: 64,
                    top: 4,
                    right: 40,
                    angle: 0.35,
                  ),
                  ArtItem.icon(
                    Icons.edit_rounded,
                    size: 48,
                    top: 50,
                    right: 0,
                    angle: -0.5,
                  ),
                ]),
                onTap: () => context.push(Routes.assignments),
              ),
              const SizedBox(height: 4),
              HomeOptionCard(
                icon: Icons.school_rounded,
                title: 'Exámenes',
                subtitle: 'Pruebas y exámenes de ${child.name}',
                color: const Color(0xFFE5484D),
                art: const ArtCluster([
                  ArtItem.text('A+', size: 56, top: 6, right: 30, angle: -0.2),
                  ArtItem.icon(
                    Icons.check_circle_rounded,
                    size: 44,
                    top: 56,
                    right: 0,
                    angle: 0.2,
                  ),
                ]),
                onTap: () => context.push(Routes.exams),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tarjeta grande de un hijo: nombre y resumen del perfil.
class _ChildCard extends StatelessWidget {
  const _ChildCard({
    required this.child,
    required this.color,
    required this.selected,
  });

  final ChildBrief child;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(color);
    final ink = Brutal.ink(context);
    final initial = child.name.isEmpty ? '?' : child.name[0].toUpperCase();

    Widget stat(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: context.textTheme.titleMedium?.copyWith(
                  color: s.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style:
                    context.textTheme.labelSmall?.copyWith(color: s.inkMuted),
              ),
            ],
          ),
        );

    return BrutalBox(
      color: s.surface,
      radius: Radii.lg,
      clip: true,
      child: Stack(
        children: [
          Positioned(
            right: -16,
            bottom: -16,
            child: Icon(
              Icons.face_rounded,
              size: 130,
              color: s.vivid.withValues(alpha: 0.16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.vivid,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(color: ink, width: Brutal.border),
                      ),
                      child: Text(
                        initial,
                        style: context.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        child.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.headlineSmall?.copyWith(
                          color: s.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (child.grade.isNotEmpty)
                  Text(
                    child.grade,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: s.inkMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const Spacer(),
                Row(
                  children: [
                    stat('Edad', child.age == null ? '—' : '${child.age} años'),
                    stat(
                      'Promedio',
                      child.average == null
                          ? '—'
                          : child.average!.toStringAsFixed(0),
                    ),
                    stat(
                      'Asistencia',
                      child.attendance == null
                          ? '—'
                          : '${child.attendance!.round()}%',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel "Promedio de asistencias" del hijo seleccionado.
class ParentAttendanceScreen extends ConsumerWidget {
  const ParentAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(parentDashboardProvider).valueOrNull ??
        ParentDashboardData.mock();
    final kids = data.children;
    final child =
        kids[ref.watch(selectedChildIndexProvider).clamp(0, kids.length - 1)];
    return StudentAttendanceScreen(
      title: 'Promedio de asistencias',
      heading: 'Asistencia de ${child.name}',
      percentOverride: child.attendance ?? data.attendancePercent,
    );
  }
}

/// Flecha lateral del carrusel (cuadro con borde y sombra).
class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.3,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: 2, bottom: 2),
            decoration: Brutal.decoration(
              context,
              color: Colors.white,
              radius: Radii.sm,
              offset: 2,
            ),
            child: Icon(icon, color: Colors.black, size: 26),
          ),
        ),
      ),
    );
  }
}
