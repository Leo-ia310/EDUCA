import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/date_utils.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/educa_bottom_nav.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../notifications/providers.dart';
import '../../data/dashboard_data.dart';
import '../../providers.dart';
import '../widgets/classmates_strip.dart';
import '../widgets/home_tile_card.dart';
import '../widgets/schedule_item.dart';
import '../widgets/student_home_header.dart';

class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user!;
    final palette = context.palette;
    // Datos reales del backend (fallback a demo mientras carga o sin backend).
    final data = ref.watch(studentDashboardProvider).valueOrNull ??
        StudentDashboardData.mock();

    // Estado del horario respecto a la hora actual: clase en curso y siguiente.
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    int? currentIdx;
    int? nextIdx;
    for (var i = 0; i < data.todaySchedule.length; i++) {
      final start = DateUtilsX.hhmmToMinutes(data.todaySchedule[i].startTime);
      final end = DateUtilsX.hhmmToMinutes(data.todaySchedule[i].endTime);
      if (nowMin >= start && nowMin < end) {
        currentIdx = i;
      } else if (start > nowMin && nextIdx == null) {
        nextIdx = i;
      }
    }
    // Etiqueta de fecha real (día de la semana capitalizado).
    final weekday = toBeginningOfSentenceCase(
      DateFormat('EEEE', 'es').format(now),
    );

    return AppScaffold(
      padding: EdgeInsets.zero,
      topSafeArea: false,
      onRefresh: () async =>
          Future<void>.delayed(const Duration(milliseconds: 600)),
      bottomNav: const EducaBottomNav(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra superior full-bleed (avatar + nombre a la izquierda,
          // acciones a la derecha), con fondo azul hasta el borde superior.
          StudentHomeHeader(
            name: user.displayFirstName,
            initials: user.displayFirstName.isNotEmpty
                ? user.displayFirstName.substring(0, 1).toUpperCase()
                : '?',
            avatarUrl: user.avatarUrl,
            notificationsBadge:
                ref.watch(notificationsUnreadProvider).asData?.value ?? 0,
            onNotificationsTap: () => context.go(Routes.alerts),
          ),
          // Panel del contenido: se monta sobre la barra azul con esquinas
          // superiores redondeadas (solape = radio), de modo que la curva
          // parezca del panel (cóncava) y no de la barra.
          Transform.translate(
            offset: const Offset(0, -_panelRadius),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_panelRadius),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 44, 16, 24),
              child: StaggeredEntrance(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Panel Principal'),
                  const SizedBox(height: 12),
                  // Grilla de accesos rápidos (tarjetas cuadradas).
                  _HomeTilesGrid(
                    tiles: [
                      _TileData(
                        icon: Icons.note_alt_rounded,
                        title: 'Tareas',
                        color: const Color(0xFFF3993E),
                        onTap: () => context.push(Routes.assignments),
                      ),
                      _TileData(
                        icon: Icons.menu_book_rounded,
                        title: 'Materias',
                        color: const Color(0xFF4C8DF5),
                        onTap: () => context.push(Routes.subjects),
                      ),
                      _TileData(
                        icon: Icons.grade_rounded,
                        title: 'Notas',
                        color: const Color(0xFF9A6BE0),
                        onTap: () => context.push(Routes.grades),
                      ),
                      _TileData(
                        icon: Icons.event_available_rounded,
                        title: 'Asistencia',
                        color: const Color(0xFF34C77A),
                        onTap: () => context.push(Routes.myAttendance),
                      ),
                      _TileData(
                        icon: Icons.calendar_month_rounded,
                        title: 'Horario',
                        color: const Color(0xFF33B7A0),
                        onTap: () => context.push(Routes.schedule),
                      ),
                      _TileData(
                        icon: Icons.groups_rounded,
                        title: 'Compañeros',
                        color: const Color(0xFFEC6A9C),
                        onTap: () => context.push(Routes.classmates),
                      ),
                    ],
                  ),
          const SizedBox(height: 24),

          // Horario de hoy
          Row(
            children: [
              const Expanded(child: SectionHeader(title: 'Horario de Hoy')),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  weekday,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: palette.accentDeep,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < data.todaySchedule.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            ScheduleItemRow(
              slot: data.todaySchedule[i],
              highlighted: i == currentIdx,
              badge: i == currentIdx
                  ? 'Ahora'
                  : i == nextIdx
                      ? _inLabel(
                          DateUtilsX.hhmmToMinutes(
                                data.todaySchedule[i].startTime,
                              ) -
                              nowMin,
                        )
                      : null,
            ),
          ],
          const SizedBox(height: 24),

          // Compañeros
          const SectionHeader(title: 'Compañeros'),
          const SizedBox(height: 12),
                ClassmatesStrip(
                  names: data.classmates,
                  extraCount: data.classmatesExtra,
                ),
              ],
            ),
          ),
        ),
        ],
      ),
    );
  }
}

/// Datos de una tarjeta cuadrada del home.
class _TileData {
  const _TileData({
    required this.icon,
    required this.title,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback? onTap;
}

/// Grilla responsiva de 3 columnas con tarjetas cuadradas (1:1).
class _HomeTilesGrid extends StatelessWidget {
  const _HomeTilesGrid({required this.tiles});

  final List<_TileData> tiles;

  @override
  Widget build(BuildContext context) {
    const cols = 3;
    const gap = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles)
              SizedBox(
                width: tileSize,
                height: tileSize,
                child: HomeTileCard(
                  icon: t.icon,
                  title: t.title,
                  color: t.color,
                  onTap: t.onTap,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Radio de la curva con que el panel se monta sobre la barra azul (cóncava).
const double _panelRadius = 24;

/// Etiqueta "En X min" / "En Yh Zm" para la próxima clase.
String _inLabel(int minutes) {
  if (minutes <= 0) return 'Ahora';
  if (minutes < 60) return 'En $minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? 'En $h h' : 'En ${h}h ${m}m';
}
