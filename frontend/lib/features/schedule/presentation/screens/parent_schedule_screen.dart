import '../../../../core/network/provider_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/brutal.dart';
import '../../../dashboard/data/dashboard_data.dart';
import '../../../dashboard/presentation/screens/parent_children_screen.dart'
    show selectedChildIndexProvider;
import '../../../dashboard/providers.dart';
import 'schedule_screen.dart';

/// Horario de un hijo (vista del padre): elige al hijo y ve sus clases,
/// recesos y turnos tal como los configuró el administrador.
class ParentScheduleScreen extends ConsumerWidget {
  const ParentScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(parentDashboardProvider).scopedValue ??
        ParentDashboardData.empty();
    final kids = data.children;
    final selected =
        ref.watch(selectedChildIndexProvider).clamp(0, kids.length - 1);
    final child = kids[selected];

    return ScheduleScreen(
      // Una pantalla por hijo: al cambiar de hijo se reinicia el estado.
      key: ValueKey('schedule-${child.id}-$selected'),
      forChild: true,
      studentId: child.id,
      title: kids.length > 1 ? 'Horario' : 'Horario de ${child.name}',
      header: kids.length > 1
          ? Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var i = 0; i < kids.length; i++)
                  BrutalPill(
                    compact: true,
                    label: kids[i].name,
                    icon: Icons.face_rounded,
                    selected: i == selected,
                    onTap: () =>
                        ref.read(selectedChildIndexProvider.notifier).state = i,
                  ),
              ],
            )
          : null,
    );
  }
}
