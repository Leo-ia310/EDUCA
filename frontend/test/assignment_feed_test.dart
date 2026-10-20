import 'dart:async';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/core/theme/app_theme.dart';
import 'package:educa360/features/assignments/data/mock_assignment_repository.dart';
import 'package:educa360/features/assignments/data/supabase_assignment_repository.dart';
import 'package:educa360/features/assignments/domain/assignment_page.dart';
import 'package:educa360/features/assignments/domain/entities.dart';
import 'package:educa360/features/assignments/presentation/controllers/assignments_list_controller.dart';
import 'package:educa360/features/assignments/presentation/screens/student_assignments_screen.dart';
import 'package:educa360/features/assignments/providers.dart';
import 'package:educa360/features/chat/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

Assignment item(String id) => Assignment(
      id: id,
      classId: 1,
      subjectName: 'Math',
      groupName: 'A',
      title: 'Task $id',
      assignedAt: DateTime(2026),
      dueAt: id == '3' ? null : DateTime(2999),
      kind: AssignmentKind.homework,
      maxScore: 100,
      allowLate: false,
      attachments: const [],
      totalStudents: 1,
      submittedCount: 0,
      gradedCount: 0,
      progress: const AssignmentProgress(),
    );

class _Repo extends MockAssignmentRepository {
  final calls = <({int? studentId, AssignmentQuery query, String? cursor})>[];
  int individualReads = 0;
  @override
  Future<AssignmentPage> assignmentPage({
    int? studentId,
    AssignmentQuery query = const AssignmentQuery(),
    String? cursor,
    int limit = 50,
  }) async {
    calls.add((studentId: studentId, query: query, cursor: cursor));
    return cursor == null
        ? AssignmentPage(items: [item('1'), item('2')], nextCursor: 'next')
        : AssignmentPage(items: [item('3')]);
  }

  @override
  Future<Submission?> submissionForStudent({
    required String assignmentId,
    required int studentId,
  }) async {
    individualReads++;
    throw StateError('Feed must include progress');
  }
}

class _Api extends BackendApiClient {
  _Api(SupabaseClient client) : super(supabase: client);
  int calls = 0;
  bool undated = false;
  String? path;
  Map<String, dynamic>? query;
  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    calls++;
    this.path = path;
    query = queryParameters;
    return {
      'nextCursor': 'opaque',
      'assignments': [
        {
          'id': '7',
          'classId': '9',
          'subjectName': 'Math',
          'groupName': 'A',
          'title': 'Example',
          'assignedAt': '2026-01-01T00:00:00Z',
          'dueAt': undated ? null : '2026-12-01T00:00:00Z',
          'kind': 'exam',
          'maxScore': 100,
          'published': true,
          'allowLate': false,
          'attachments': [],
          'totalStudents': 1,
          'submittedCount': 1,
          'gradedCount': 1,
          'progress': {'status': 'graded', 'score': 80},
        }
      ],
    };
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  test(
      'paging appends once, preserves loaded items on failure and retries the same cursor',
      () async {
    final next = Completer<AssignmentPage>();
    var calls = 0;
    final controller = AssignmentFeedController((cursor) async {
      calls++;
      if (calls == 1) {
        return AssignmentPage(items: [item('1')], nextCursor: 'a');
      }
      if (calls == 2) return next.future;
      expect(cursor, 'a');
      return AssignmentPage(items: [item('1'), item('2')]);
    });
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    final loading = controller.loadMore();
    await controller.loadMore();
    expect(calls, 2);
    next.completeError(StateError('Network interrupted'));
    await loading;
    expect(controller.state.requireValue.map((a) => a.id), ['1']);
    expect(controller.hasMore, isTrue);
    expect(controller.loadMoreError, isNotNull);
    await controller.loadMore();
    expect(controller.state.requireValue.map((a) => a.id), ['1', '2']);
    expect(controller.hasMore, isFalse);
    await controller.loadMore();
    expect(calls, 3);
  });

  test(
      'different students and subjects have separate cursor streams and server filters',
      () async {
    final repo = _Repo();
    final scoped = ProviderContainer(
      overrides: [assignmentRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(scoped.dispose);
    final first = studentAssignmentsProvider(
      (studentId: 101, exams: false, subject: 'Math'),
    );
    final second = studentAssignmentsProvider(
      (studentId: 202, exams: true, subject: null),
    );
    final a = scoped.listen(first, (_, __) {}),
        b = scoped.listen(second, (_, __) {});
    addTearDown(a.close);
    addTearDown(b.close);
    await Future<void>.delayed(Duration.zero);
    expect(repo.calls.map((c) => c.studentId), [101, 202]);
    expect(repo.calls.first.query.subject, 'Math');
    expect(
      repo.calls.last.query.kinds,
      [AssignmentKind.exam, AssignmentKind.quiz],
    );
    await scoped.read(first.notifier).loadMore();
    expect(scoped.read(first).requireValue.length, 3);
    expect(scoped.read(second).requireValue.length, 2);
    expect(repo.calls.last.studentId, 101);
  });

  test(
      'one API request returns a page including student progress and accepts string class IDs',
      () async {
    final client =
        SupabaseClient('https://fixture.supabase.co', 'public-fixture');
    addTearDown(client.dispose);
    final api = _Api(client);
    final captured = SupabaseAssignmentRepository(
      client: client,
      api: api,
      institutionId: 1,
    );
    final page = await captured.assignmentPage(
      studentId: 202,
      query: const AssignmentQuery(kinds: [AssignmentKind.exam]),
    );
    expect(api.calls, 1);
    expect(api.path, '/assignments/student');
    expect(api.query?['studentId'], 202);
    expect(api.query?['kinds'], 'exam');
    expect(page.items.single.classId, 9);
    expect(page.items.single.progress?.score, 80);
    expect(page.nextCursor, 'opaque');
    api.undated = true;
    expect((await captured.assignmentPage(studentId: 202)).items.single.dueAt,
        isNull,);
    final empty = await captured.assignmentPage(
        studentId: 202, query: const AssignmentQuery(kinds: []),);
    expect(empty.items, isEmpty);
    expect(api.calls, 2);
  });

  test('a disposed query ignores its late first response', () async {
    final pending = Completer<AssignmentPage>();
    final controller = AssignmentFeedController((_) => pending.future);
    controller.dispose();
    pending.complete(AssignmentPage(items: [item('old')]));
    await Future<void>.delayed(Duration.zero);
  });

  test(
      'undated tasks stay open and sort after dated tasks without invented deadlines',
      () {
    expect(item('3').statusForNow(DateTime(3000)), AssignmentStatus.open);
    final sorted = [item('3'), item('2'), item('1')]
      ..sort(Assignment.compareByDueDate);
    expect(sorted.map((a) => a.id), ['1', '2', '3']);
  });

  test('demo pages filter before selecting a page', () async {
    final repo = MockAssignmentRepository();
    final expected = (await repo.assignmentsForTeacher())
        .where((a) => a.kind == AssignmentKind.exam)
        .toList()
      ..sort(Assignment.compareByDueDate);
    final ids = <String>[];
    String? cursor;
    do {
      final page = await repo.assignmentPage(
          query: const AssignmentQuery(kinds: [AssignmentKind.exam]),
          cursor: cursor,
          limit: 1,);
      ids.addAll(page.items.map((a) => a.id));
      cursor = page.nextCursor;
    } while (cursor != null);
    expect(ids, expected.map((a) => a.id));
    final empty = await repo.assignmentPage(
        query: const AssignmentQuery(search: 'no matching task'),);
    expect(empty.items, isEmpty);
    expect(empty.nextCursor, isNull);
    final child = await repo.assignmentPage(
        studentId: 1001, query: const AssignmentQuery(subject: 'Matemáticas'),);
    expect(child.items, isNotEmpty);
    expect(child.items.every((a) => a.progress != null), isTrue);
  });

  testWidgets(
      'student list renders progress and loads next page without per-card reads',
      (tester) async {
    final repo = _Repo();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) =>
              const SubjectAssignmentsScreen(studentId: 202, subject: 'Math'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assignmentRepositoryProvider.overrideWithValue(repo),
          totalUnreadProvider.overrideWith((ref) => Stream.value(0)),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.lightTheme,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Task 1'), findsOneWidget);
    expect(repo.individualReads, 0);
    await tester.ensureVisible(find.text('Cargar más'));
    await tester.tap(find.text('Cargar más'));
    await tester.pumpAndSettle();
    expect(repo.calls.length, 2);
    expect(repo.calls.last.studentId, 202);
    expect(repo.individualReads, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
