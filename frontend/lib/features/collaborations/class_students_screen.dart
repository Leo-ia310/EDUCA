import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/supabase_client.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../dashboard/presentation/widgets/student_chrome.dart';
import 'providers.dart';

final classStudentsProvider = FutureProvider.family<List<Map<String, dynamic>>, int>((ref, classId) async {
  final allowed = await ref.watch(collaborationWorkspaceProvider.future);
  if (!(allowed['classes'] as List).any((c) => c['classId'] == classId && (c['permissions'] as List).contains('students.view'))) {
    throw StateError('No tienes permiso para ver los estudiantes de esta clase.');
  }
  final client = ref.watch(supabaseClientProvider);
  if (client == null) throw StateError('Se requiere conexión para consultar estudiantes.');
  final cls = await client.from('classes').select('group_id').eq('id', classId).single();
  final rows = await client.from('enrollments').select('students(id, student_code, persons(first_name, last_name))').eq('group_id', (cls['group_id'] as num).toInt());
  return rows.map((row) => row['students']).whereType<Map<String, dynamic>>().toList();
});

class ClassStudentsScreen extends ConsumerWidget {
  const ClassStudentsScreen({super.key, required this.classId});
  final int classId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => StudentDetailScaffold(title: 'Estudiantes', bottomNav: false,
    child: ref.watch(classStudentsProvider(classId)).when(loading: () => const SkeletonList(),
      error: (e, _) => ErrorStateView(message: '$e', onRetry: () => ref.invalidate(classStudentsProvider(classId))),
      data: (students) => students.isEmpty ? const EmptyState(icon: Icons.group_outlined, title: 'Sin estudiantes') : Column(children: [
        for (final student in students) ListTile(leading: const Icon(Icons.person_rounded),
          title: Text('${student['persons']?['first_name'] ?? ''} ${student['persons']?['last_name'] ?? ''}'),
          subtitle: Text(student['student_code'] as String? ?? ''),),
      ],),),);
}
