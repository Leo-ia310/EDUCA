import 'dart:async';
import 'package:educa360/core/network/backend_api_client.dart';
import 'package:educa360/features/assignments/data/mock_assignment_repository.dart';
import 'package:educa360/features/assignments/domain/entities.dart';
import 'package:educa360/features/assignments/presentation/controllers/assignment_form_controller.dart';
import 'package:educa360/features/assignments/providers.dart';
import 'package:educa360/features/auth/data/mock_auth_repository.dart';
import 'package:educa360/features/auth/domain/auth_repository.dart';
import 'package:educa360/features/auth/presentation/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends MockAuthRepository {
  @override
  Future<AuthSession?> currentSession() async => null;
}

class _LostResponseRepository extends MockAssignmentRepository {
  final attempts = <AssignmentDraft>[];
  final receipts = <String, Assignment>{};
  final tasks = <String, Assignment>{};
  Completer<void>? gate;
  bool rejectFirst = false;
  @override
  Future<Assignment> upsertAssignment(AssignmentDraft draft) async {
    attempts.add(draft);
    if (rejectFirst && attempts.length == 1) {
      throw BackendApiException(
        'Invalid field',
        statusCode: 400,
        code: 'validation_error',
      );
    }
    if (gate != null && attempts.length == 1) await gate!.future;
    final replay = receipts[draft.idempotencyKey];
    if (replay != null) return replay;
    final id = draft.assignmentId ?? 'created-${tasks.length + 1}';
    final task = Assignment(
      id: id,
      classId: draft.classId,
      subjectName: 'Math',
      groupName: 'A',
      title: draft.title,
      assignedAt: DateTime(2026),
      dueAt: draft.dueAt,
      kind: draft.kind,
      maxScore: draft.maxScore,
      allowLate: draft.allowLate,
      attachments: draft.attachments,
      totalStudents: 0,
      submittedCount: 0,
      gradedCount: 0,
    );
    tasks[id] = task;
    receipts[draft.idempotencyKey!] = task;
    if (attempts.length == 1) throw StateError('Response lost after commit');
    return task;
  }
}

Future<ProviderContainer> _containerFor(_LostResponseRepository repo) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_Auth()),
      assignmentRepositoryProvider.overrideWithValue(repo),
    ],
  );
  container.read(authControllerProvider);
  await Future<void>.delayed(Duration.zero);
  return container;
}

void main() {
  test(
      'a definitive validation rejection allows corrected fields without retrying the invalid draft',
      () async {
    final repo = _LostResponseRepository()..rejectFirst = true;
    final container = await _containerFor(repo);
    addTearDown(container.dispose);
    final listener =
        container.listen(assignmentFormControllerProvider, (_, __) {});
    addTearDown(listener.close);
    final controller =
        container.read(assignmentFormControllerProvider.notifier);
    controller.setClass(1);
    controller.setTitle('Invalid');
    expect(await controller.save(), isNull);
    controller.setTitle('Corrected');
    expect((await controller.save())!.title, 'Corrected');
    expect(repo.attempts.length, 2);
    expect(
      repo.attempts[1].idempotencyKey,
      isNot(repo.attempts[0].idempotencyKey),
    );
    expect(repo.tasks.length, 1);
  });
  test(
      'lost creation response retains its key across navigation; later saves update the confirmed task',
      () async {
    final repo = _LostResponseRepository();
    final active = await _containerFor(repo);
    addTearDown(active.dispose);
    final listener =
        active.listen(assignmentFormControllerProvider, (_, __) {});
    final controller = active.read(assignmentFormControllerProvider.notifier);
    controller.setClass(1);
    controller.setTitle('Original');
    expect(await controller.save(), isNull);
    listener.close();
    await active.pump();
    expect(
      identical(
        active.read(assignmentFormControllerProvider.notifier),
        controller,
      ),
      isTrue,
    );
    final secondListener =
        active.listen(assignmentFormControllerProvider, (_, __) {});
    addTearDown(secondListener.close);
    final saved = await controller.save();
    expect(saved, isNotNull);
    expect(repo.attempts[0].idempotencyKey, repo.attempts[1].idempotencyKey);
    expect(repo.tasks.length, 1);
    controller.setTitle('Edited');
    final edited = await controller.save();
    expect(edited!.id, saved!.id);
    expect(repo.tasks.length, 1);
    expect(
      repo.attempts.last.idempotencyKey,
      isNot(repo.attempts.first.idempotencyKey),
    );
  });
  test(
      'editing an unconfirmed creation first reconciles the original receipt, then updates its id',
      () async {
    final repo = _LostResponseRepository();
    final active = await _containerFor(repo);
    addTearDown(active.dispose);
    final listener =
        active.listen(assignmentFormControllerProvider, (_, __) {});
    addTearDown(listener.close);
    final controller = active.read(assignmentFormControllerProvider.notifier);
    controller.setClass(1);
    controller.setTitle('Original');
    expect(await controller.save(), isNull);
    controller.setTitle('New content');
    final saved = await controller.save();
    expect(saved!.title, 'New content');
    expect(repo.attempts.length, 3);
    expect(repo.attempts[1].title, 'Original');
    expect(repo.attempts[1].idempotencyKey, repo.attempts[0].idempotencyKey);
    expect(repo.attempts[2].assignmentId, saved.id);
    expect(repo.tasks.length, 1);
  });
  test('double tap does not start another write while the first is unresolved',
      () async {
    final repo = _LostResponseRepository()..gate = Completer<void>();
    final container = await _containerFor(repo);
    addTearDown(container.dispose);
    final listener =
        container.listen(assignmentFormControllerProvider, (_, __) {});
    addTearDown(listener.close);
    final controller =
        container.read(assignmentFormControllerProvider.notifier);
    controller.setClass(1);
    controller.setTitle('Original');
    final pending = controller.save();
    expect(await controller.save(), isNull);
    expect(repo.attempts.length, 1);
    repo.gate!.complete();
    expect(await pending, isNull);
    expect(await controller.save(), isNotNull);
    expect(repo.tasks.length, 1);
  });
}
