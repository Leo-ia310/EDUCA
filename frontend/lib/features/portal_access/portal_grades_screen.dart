import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/backend_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/depth_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../dashboard/presentation/widgets/student_chrome.dart';
import 'access_widgets.dart';
import 'providers.dart';

final portalGradesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({int studentId, String? periodId})>(
        (ref, args) async {
  final access = await ref.watch(portalAccessProvider.future);
  if (!access.gradeVisible(args.studentId, args.periodId)) {
    throw StateError(
      'Las notas de este periodo están ocultas por la institución.',
    );
  }
  final data = await ref.watch(backendApiClientProvider)!.get(
    '/portal-access/grades',
    queryParameters: {
      'studentId': args.studentId,
      if (args.periodId != null) 'periodId': args.periodId,
    },
  );
  return ((data as Map)['grades'] as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
});

class PortalGradesScreen extends ConsumerStatefulWidget {
  const PortalGradesScreen({super.key});
  @override
  ConsumerState<PortalGradesScreen> createState() => _PortalGradesScreenState();
}

class _PortalGradesScreenState extends ConsumerState<PortalGradesScreen> {
  int? _student;
  String? _period;
  @override
  Widget build(BuildContext context) => StudentDetailScaffold(
        title: 'Notas',
        bottomNav: false,
        onRefresh: () async {
          ref.invalidate(portalAccessProvider);
          ref.invalidate(portalGradesProvider);
          await ref.read(portalAccessProvider.future);
        },
        child: ref.watch(portalAccessProvider).when(
              loading: () => const SkeletonList(),
              error: (e, _) => ErrorStateView(
                message: 'No se pudieron verificar tus accesos.',
                onRetry: () => ref.invalidate(portalAccessProvider),
              ),
              data: (access) {
                if (access.students.isEmpty) {
                  return const EmptyState(
                    icon: Icons.person_off_outlined,
                    title: 'Sin estudiante vinculado',
                  );
                }
                final student = access.students.firstWhere(
                  (s) => s['studentId'] == _student,
                  orElse: () => access.students.first,
                );
                final sid = student['studentId'] as int;
                final visible = access.gradeVisible(sid, _period);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (access.students.length > 1)
                      DropdownButtonFormField<int>(
                        initialValue: sid,
                        decoration:
                            const InputDecoration(labelText: 'Estudiante'),
                        items: [
                          for (final s in access.students)
                            DropdownMenuItem(
                              value: s['studentId'] as int,
                              child: Text(s['name'] as String),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          _student = v;
                          _period = null;
                        }),
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(sid),
                      initialValue: _period,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Periodo / trimestre',
                      ),
                      items: [
                        const DropdownMenuItem<String>(child: Text('Anual')),
                        for (final p in student['periods'] as List)
                          DropdownMenuItem(
                            value: p['id'].toString(),
                            child: Text(
                              '${p['name']}${p['visible'] == true ? '' : ' · oculto'}',
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _period = v),
                    ),
                    const SizedBox(height: 16),
                    if (!visible)
                      const PortalRestriction(
                        message:
                            'Las notas de este estudiante o periodo están ocultas. Puedes seleccionar otro periodo habilitado.',
                      )
                    else
                      ref
                          .watch(
                            portalGradesProvider(
                              (studentId: sid, periodId: _period),
                            ),
                          )
                          .when(
                            loading: () => const SkeletonList(),
                            error: (e, _) => ErrorStateView(
                              message: 'No se pudieron cargar las notas. $e',
                              onRetry: () =>
                                  ref.invalidate(portalGradesProvider),
                            ),
                            data: (rows) => rows.isEmpty
                                ? const EmptyState(
                                    icon: Icons.assessment_outlined,
                                    title: 'Sin notas registradas',
                                  )
                                : Column(
                                    children: [
                                      for (final row in rows)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: DepthCard(
                                            soft: true,
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${row['evaluations']?['classes']?['subjects']?['name'] ?? 'Materia'}',
                                                  style: context
                                                      .textTheme.titleSmall,
                                                ),
                                                Text(
                                                  '${row['evaluations']?['title'] ?? 'Evaluación'}',
                                                ),
                                                Text(
                                                  '${row['score'] ?? '—'} / ${row['evaluations']?['max_score'] ?? 100}',
                                                  style: context
                                                      .textTheme.headlineSmall,
                                                ),
                                                if (row['notes'] != null)
                                                  Text(
                                                    row['notes'] as String,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                  ],
                );
              },
            ),
      );
}
