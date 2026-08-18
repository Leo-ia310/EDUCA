import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities.dart';
import '../../providers.dart';

/// Filtros que la UI puede aplicar al listado.
class AssignmentsFilter {
  const AssignmentsFilter({
    this.classId,
    this.kind,
    this.onlyOpen = false,
    this.searchText = '',
  });

  final int? classId;
  final AssignmentKind? kind;
  final bool onlyOpen;
  final String searchText;

  AssignmentsFilter copyWith({
    int? classId,
    AssignmentKind? kind,
    bool? onlyOpen,
    String? searchText,
    bool clearClass = false,
    bool clearKind = false,
  }) {
    return AssignmentsFilter(
      classId: clearClass ? null : (classId ?? this.classId),
      kind: clearKind ? null : (kind ?? this.kind),
      onlyOpen: onlyOpen ?? this.onlyOpen,
      searchText: searchText ?? this.searchText,
    );
  }
}

final assignmentsFilterProvider =
    StateProvider<AssignmentsFilter>((ref) => const AssignmentsFilter());

/// Lista para el docente (todas las tareas que asigna, agnóstico al rol).
final teacherAssignmentsProvider =
    FutureProvider.autoDispose<List<Assignment>>((ref) async {
  final repo = ref.watch(assignmentRepositoryProvider);
  final filter = ref.watch(assignmentsFilterProvider);
  final list = await repo.assignmentsForTeacher(classId: filter.classId);
  return _applyFilters(list, filter);
});

/// Lista para el estudiante / padre (tareas asignadas a sus clases).
final studentAssignmentsProvider =
    FutureProvider.autoDispose<List<Assignment>>((ref) async {
  final repo = ref.watch(assignmentRepositoryProvider);
  final filter = ref.watch(assignmentsFilterProvider);
  final list = await repo.assignmentsForStudent();
  return _applyFilters(list, filter);
});

List<Assignment> _applyFilters(
    List<Assignment> list, AssignmentsFilter filter) {
  final now = DateTime.now();
  Iterable<Assignment> filtered = list;
  if (filter.kind != null) {
    filtered = filtered.where((a) => a.kind == filter.kind);
  }
  if (filter.onlyOpen) {
    filtered = filtered.where((a) {
      final s = a.statusForNow(now);
      return s == AssignmentStatus.open || s == AssignmentStatus.dueSoon;
    });
  }
  final text = filter.searchText.trim().toLowerCase();
  if (text.isNotEmpty) {
    filtered = filtered.where((a) =>
        a.title.toLowerCase().contains(text) ||
        a.subjectName.toLowerCase().contains(text));
  }
  return filtered.toList();
}
