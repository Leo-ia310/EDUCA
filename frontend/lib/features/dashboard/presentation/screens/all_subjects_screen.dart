import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/open_card.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../../data/dashboard_data.dart';
import '../../domain/dashboard_models.dart';
import '../../providers.dart';
import '../widgets/student_chrome.dart';
import '../widgets/subject_card.dart';
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
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _SubjectTile(subject: subjects[i])),
                const SizedBox(width: 12),
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
      closed: (context, open) => SubjectProgressCard(
        subject: subject,
        onTap: open,
      ),
      open: (context) => SubjectDetailScreen(subject: subject),
    );
  }
}
