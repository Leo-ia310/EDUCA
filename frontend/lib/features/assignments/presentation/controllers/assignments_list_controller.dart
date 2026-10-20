import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';
import '../../domain/assignment_page.dart';
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

/// Marcado personal "hecha" del alumno sobre sus tareas (capa local de
/// productividad, independiente del estado oficial de entrega). Se alterna con
/// el swipe en el feed de tareas.
class TasksDoneNotifier extends StateNotifier<Set<String>> {
  TasksDoneNotifier() : super(const {});

  void toggle(String assignmentId) {
    final next = {...state};
    if (!next.add(assignmentId)) next.remove(assignmentId);
    state = next;
  }
}

final tasksDoneProvider = StateNotifierProvider<TasksDoneNotifier, Set<String>>(
  (ref) => TasksDoneNotifier(),
);

/// Owns one cursor stream. Refresh invalidates this controller, so responses
/// from a disposed query cannot overwrite a different student or filter.
class AssignmentFeedController
    extends StateNotifier<AsyncValue<List<Assignment>>> {
  AssignmentFeedController(this._load) : super(const AsyncValue.loading()) {
    unawaited(_initial());
  }
  final Future<AssignmentPage> Function(String? cursor) _load;
  String? _nextCursor;
  bool loadingMore = false;
  Object? loadMoreError;
  bool get hasMore => _nextCursor != null;

  Future<void> _initial() async {
    try {
      final page = await _load(null);
      if (!mounted) return;
      _nextCursor = page.nextCursor;
      state = AsyncValue.data(List.unmodifiable(page.items));
    } catch (error, stack) {
      if (mounted) state = AsyncValue.error(error, stack);
    }
  }

  Future<void> loadMore() async {
    final items = state.valueOrNull;
    if (loadingMore || !hasMore || items == null) return;
    final cursor = _nextCursor;
    loadingMore = true;
    loadMoreError = null;
    state = AsyncValue.data(List.unmodifiable(items));
    try {
      final page = await _load(cursor);
      if (!mounted) return;
      if (page.nextCursor != null && page.nextCursor == cursor) {
        throw StateError('El servidor no avanzó el cursor de tareas.');
      }
      _nextCursor = page.nextCursor;
      loadingMore = false;
      state = AsyncValue.data(List.unmodifiable({
        for (final item in items) item.id: item,
        for (final item in page.items) item.id: item,
      }.values,),);
    } catch (error) {
      if (!mounted) return;
      loadingMore = false;
      loadMoreError = error;
      state = AsyncValue.data(List.unmodifiable(items));
    }
  }
}

AssignmentQuery _query(AssignmentsFilter filter,
    {String? subject, List<AssignmentKind>? kinds,}) {
  final selected = filter.kind == null
      ? kinds
      : (kinds == null || kinds.contains(filter.kind)
          ? [filter.kind!]
          : <AssignmentKind>[]);
  return AssignmentQuery(
      classId: filter.classId,
      kinds: selected,
      onlyOpen: filter.onlyOpen,
      search: filter.searchText,
      subject: subject,);
}

final teacherAssignmentsProvider = StateNotifierProvider.autoDispose
    .family<AssignmentFeedController, AsyncValue<List<Assignment>>, String?>(
        (ref, subject) {
  final repo = ref.watch(assignmentRepositoryProvider);
  final query = _query(ref.watch(assignmentsFilterProvider), subject: subject);
  return AssignmentFeedController(
      (cursor) => repo.assignmentPage(query: query, cursor: cursor),);
});

typedef StudentAssignmentFeed = ({int studentId, bool exams, String? subject});
final studentAssignmentsProvider = StateNotifierProvider.autoDispose.family<
    AssignmentFeedController,
    AsyncValue<List<Assignment>>,
    StudentAssignmentFeed>((ref, feed) {
  final repo = ref.watch(assignmentRepositoryProvider);
  final query = _query(ref.watch(assignmentsFilterProvider),
      subject: feed.subject,
      kinds: feed.exams
          ? [AssignmentKind.exam, AssignmentKind.quiz]
          : [
              AssignmentKind.homework,
              AssignmentKind.project,
              AssignmentKind.presentation,
            ],);
  return AssignmentFeedController((cursor) => repo.assignmentPage(
      studentId: feed.studentId, query: query, cursor: cursor,),);
});
