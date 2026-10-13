import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../data/admin_backend_repository.dart';
import '../../data/admin_schedule.dart';
import '../../data/school_directory.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/schedule_form.dart';

/// Horarios escolares: clases por día y hora, recesos y turnos, por grupo.
/// Lo que se guarda aquí es lo que ven alumnos, padres y maestros.
class AdminSchedulesScreen extends ConsumerStatefulWidget {
  const AdminSchedulesScreen({super.key});

  @override
  ConsumerState<AdminSchedulesScreen> createState() =>
      _AdminSchedulesScreenState();
}

class _AdminSchedulesScreenState extends ConsumerState<AdminSchedulesScreen> {
  String? _groupId; // null = todos
  int? _weekday; // null = todos

  static const _title = 'Horarios';

  @override
  Widget build(BuildContext context) {
    final schedules = ref.watch(adminSchedulesProvider);
    final dir = ref.watch(adminSchoolDirectoryProvider).valueOrNull ??
        const SchoolDirectory();
    final me = ref.watch(authControllerProvider).user;
    final canCreate = me?.can('schedules.create') ?? false;
    final canEdit = me?.can('schedules.edit') ?? false;

    return StudentDetailScaffold(
      title: _title,
      bottomNav: false,
      child: schedules.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => ErrorStateView(
          message: '$e',
          onRetry: () => ref.invalidate(adminSchedulesProvider),
        ),
        data: (all) => _content(context, all, dir, canCreate, canEdit),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    List<AdminScheduleEntry> all,
    SchoolDirectory dir,
    bool canCreate,
    bool canEdit,
  ) {
    final palette = context.palette;
    // Recesos de toda la institución (sin grupo) se muestran en cualquier grupo.
    final shown = all
        .where(
          (s) =>
              (_groupId == null || s.groupId == null || s.groupId == _groupId) &&
              (_weekday == null || s.weekdayId == _weekday),
        )
        .toList()
      ..sort((a, b) {
        final byDay = a.weekdayId.compareTo(b.weekdayId);
        return byDay != 0 ? byDay : a.startTime.compareTo(b.startTime);
      });

    final days = {for (final s in shown) s.weekdayId}.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canCreate) ...[
          BrutalButton(
            expand: true,
            onTap: () => showScheduleSheet(
              context,
              groupId: _groupId,
              weekdayId: _weekday,
            ),
            icon: Icons.add_rounded,
            label: 'Nuevo horario',
          ),
          const SizedBox(height: 16),
        ],
        const FormLabel('Grupo'),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            BrutalPill(
              compact: true,
              label: 'Todos',
              selected: _groupId == null,
              onTap: () => setState(() => _groupId = null),
            ),
            for (final g in dir.groups)
              BrutalPill(
                compact: true,
                label: g.name,
                selected: _groupId == g.id,
                onTap: () => setState(() => _groupId = g.id),
              ),
          ],
        ),
        const FormLabel('Día'),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            BrutalPill(
              compact: true,
              label: 'Todos',
              selected: _weekday == null,
              onTap: () => setState(() => _weekday = null),
            ),
            for (final d in scheduleWeekdays)
              BrutalPill(
                compact: true,
                label: d.$2,
                selected: _weekday == d.$1,
                onTap: () => setState(() => _weekday = d.$1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          const EmptyState(
            icon: Icons.schedule_rounded,
            title: 'Sin horarios',
            subtitle: 'Crea el primer horario con "Nuevo horario".',
          )
        else
          for (final day in days) ...[
            SectionHeader(title: weekdayLabel(day), accent: false),
            const SizedBox(height: 8),
            for (final s in shown.where((x) => x.weekdayId == day))
              AdminTile(
                title: s.subject,
                subtitle: [
                  '${s.startTime} – ${s.endTime}',
                  if (s.teacher != null) s.teacher!,
                ].join(' · '),
                caption: [
                  if (s.isBreak) 'Receso',
                  if (s.groupName != null) s.groupName!,
                  if (s.groupName == null && s.isBreak) 'Todos los grupos',
                  if (s.room != null && s.room!.isNotEmpty) s.room!,
                  if (shiftLabel(s.shift).isNotEmpty) shiftLabel(s.shift),
                ].join(' · '),
                color: s.isBreak ? palette.sun : subjectTone(s.subject),
                leadingIcon: s.isBreak
                    ? Icons.free_breakfast_rounded
                    : Icons.menu_book_rounded,
                onTap: canEdit ? () => showScheduleSheet(context, existing: s) : null,
              ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}
