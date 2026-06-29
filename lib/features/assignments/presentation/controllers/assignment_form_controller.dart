import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities.dart';
import '../../providers.dart';

class AssignmentFormState {
  AssignmentFormState({
    this.assignmentId,
    this.classId,
    this.title = '',
    this.description = '',
    this.instructions = '',
    this.kind = AssignmentKind.homework,
    DateTime? dueAt,
    this.maxScore = 100,
    this.allowLate = false,
    this.published = true,
    this.attachments = const [],
    this.saving = false,
    this.uploading = false,
    this.error,
  }) : dueAt = dueAt ?? DateTime.now().add(const Duration(days: 7));

  final String? assignmentId;
  final int? classId;
  final String title;
  final String description;
  final String instructions;
  final AssignmentKind kind;
  final DateTime dueAt;
  final double maxScore;
  final bool allowLate;
  final bool published;
  final List<AssignmentAttachment> attachments;
  final bool saving;
  final bool uploading;
  final String? error;

  bool get isValid => title.trim().isNotEmpty && classId != null && maxScore > 0;

  AssignmentFormState copyWith({
    String? assignmentId,
    int? classId,
    String? title,
    String? description,
    String? instructions,
    AssignmentKind? kind,
    DateTime? dueAt,
    double? maxScore,
    bool? allowLate,
    bool? published,
    List<AssignmentAttachment>? attachments,
    bool? saving,
    bool? uploading,
    String? error,
    bool clearError = false,
  }) {
    return AssignmentFormState(
      assignmentId: assignmentId ?? this.assignmentId,
      classId: classId ?? this.classId,
      title: title ?? this.title,
      description: description ?? this.description,
      instructions: instructions ?? this.instructions,
      kind: kind ?? this.kind,
      dueAt: dueAt ?? this.dueAt,
      maxScore: maxScore ?? this.maxScore,
      allowLate: allowLate ?? this.allowLate,
      published: published ?? this.published,
      attachments: attachments ?? this.attachments,
      saving: saving ?? this.saving,
      uploading: uploading ?? this.uploading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AssignmentFormController extends StateNotifier<AssignmentFormState> {
  AssignmentFormController(this._ref) : super(AssignmentFormState());
  final Ref _ref;

  void hydrate(Assignment a) {
    state = AssignmentFormState(
      assignmentId: a.id,
      classId: a.classId,
      title: a.title,
      description: a.description ?? '',
      instructions: a.instructions ?? '',
      kind: a.kind,
      dueAt: a.dueAt,
      maxScore: a.maxScore,
      allowLate: a.allowLate,
      published: a.published,
      attachments: a.attachments,
    );
  }

  void setTitle(String v) => state = state.copyWith(title: v);
  void setDescription(String v) => state = state.copyWith(description: v);
  void setInstructions(String v) => state = state.copyWith(instructions: v);
  void setKind(AssignmentKind v) => state = state.copyWith(kind: v);
  void setDueAt(DateTime v) => state = state.copyWith(dueAt: v);
  void setMaxScore(double v) => state = state.copyWith(maxScore: v);
  void setClass(int id) => state = state.copyWith(classId: id);
  void setAllowLate(bool v) => state = state.copyWith(allowLate: v);
  void setPublished(bool v) => state = state.copyWith(published: v);

  Future<void> addFiles(List<File> files) async {
    if (files.isEmpty) return;
    state = state.copyWith(uploading: true, clearError: true);
    final uploader = _ref.read(fileUploadServiceProvider);
    final next = [...state.attachments];
    try {
      for (final f in files) {
        final att =
            await uploader.upload(file: f, folder: 'assignments/_drafts');
        next.add(att);
      }
      state = state.copyWith(attachments: next, uploading: false);
    } catch (e) {
      state =
          state.copyWith(uploading: false, error: 'No se pudo subir: $e');
    }
  }

  void removeAttachment(String id) {
    state = state.copyWith(
      attachments: state.attachments.where((a) => a.id != id).toList(),
    );
  }

  Future<Assignment?> save() async {
    if (!state.isValid) {
      state = state.copyWith(error: 'Completa título, clase y puntaje.');
      return null;
    }
    state = state.copyWith(saving: true, clearError: true);
    try {
      final repo = _ref.read(assignmentRepositoryProvider);
      final created = await repo.upsertAssignment(AssignmentDraft(
        assignmentId: state.assignmentId,
        classId: state.classId!,
        title: state.title.trim(),
        description: state.description.trim().isEmpty
            ? null
            : state.description.trim(),
        instructions: state.instructions.trim().isEmpty
            ? null
            : state.instructions.trim(),
        kind: state.kind,
        dueAt: state.dueAt,
        maxScore: state.maxScore,
        allowLate: state.allowLate,
        published: state.published,
        attachments: state.attachments,
      ));
      state = state.copyWith(saving: false);
      return created;
    } catch (e) {
      state = state.copyWith(saving: false, error: 'No se pudo guardar: $e');
      return null;
    }
  }
}

final assignmentFormControllerProvider = StateNotifierProvider.autoDispose<
    AssignmentFormController, AssignmentFormState>((ref) {
  return AssignmentFormController(ref);
});
