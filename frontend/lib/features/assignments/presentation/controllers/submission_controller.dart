import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities.dart';
import '../../providers.dart';
import 'assignment_detail_controller.dart';
import 'assignments_list_controller.dart';

class SubmissionFormState {
  const SubmissionFormState({
    this.assignmentId = '',
    this.studentId = 0,
    this.notes = '',
    this.attachments = const [],
    this.saving = false,
    this.uploading = false,
    this.error,
  });

  final String assignmentId;
  final int studentId;
  final String notes;
  final List<AssignmentAttachment> attachments;
  final bool saving;
  final bool uploading;
  final String? error;

  SubmissionFormState copyWith({
    String? assignmentId,
    int? studentId,
    String? notes,
    List<AssignmentAttachment>? attachments,
    bool? saving,
    bool? uploading,
    String? error,
    bool clearError = false,
  }) {
    return SubmissionFormState(
      assignmentId: assignmentId ?? this.assignmentId,
      studentId: studentId ?? this.studentId,
      notes: notes ?? this.notes,
      attachments: attachments ?? this.attachments,
      saving: saving ?? this.saving,
      uploading: uploading ?? this.uploading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SubmissionController extends StateNotifier<SubmissionFormState> {
  SubmissionController(this._ref) : super(const SubmissionFormState());
  final Ref _ref;

  void hydrate({
    required String assignmentId,
    required int studentId,
    Submission? existing,
  }) {
    state = SubmissionFormState(
      assignmentId: assignmentId,
      studentId: studentId,
      notes: existing?.studentNotes ?? '',
      attachments: existing?.attachments ?? const [],
    );
  }

  void setNotes(String v) => state = state.copyWith(notes: v);

  Future<void> addFiles(List<File> files) async {
    if (files.isEmpty) return;
    state = state.copyWith(uploading: true, clearError: true);
    try {
      final uploader = _ref.read(fileUploadServiceProvider);
      final list = [...state.attachments];
      for (final f in files) {
        final att = await uploader.upload(
          file: f,
          folder: 'submissions/${state.assignmentId}',
        );
        list.add(att);
      }
      state = state.copyWith(attachments: list, uploading: false);
    } catch (e) {
      state = state.copyWith(uploading: false, error: 'Subida fallida: $e');
    }
  }

  void removeAttachment(String id) {
    state = state.copyWith(
      attachments: state.attachments.where((a) => a.id != id).toList(),
    );
  }

  Future<Submission?> submit() async {
    if (state.attachments.isEmpty && state.notes.trim().isEmpty) {
      state = state.copyWith(
          error: 'Adjunta al menos un archivo o agrega un comentario.');
      return null;
    }
    state = state.copyWith(saving: true, clearError: true);
    try {
      final result = await _ref.read(assignmentRepositoryProvider).submit(
            assignmentId: state.assignmentId,
            studentId: state.studentId,
            attachments: state.attachments,
            notes: state.notes.trim().isEmpty ? null : state.notes.trim(),
          );
      _ref.invalidate(mySubmissionProvider((
        assignmentId: state.assignmentId,
        studentId: state.studentId,
      )));
      _ref.invalidate(assignmentByIdProvider(state.assignmentId));
      _ref.invalidate(studentAssignmentsProvider);
      state = state.copyWith(saving: false);
      return result;
    } catch (e) {
      state = state.copyWith(saving: false, error: 'No se pudo enviar: $e');
      return null;
    }
  }
}

final submissionControllerProvider = StateNotifierProvider.autoDispose<
    SubmissionController, SubmissionFormState>((ref) {
  return SubmissionController(ref);
});
