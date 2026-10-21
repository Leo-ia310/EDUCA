import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities.dart';
import '../../providers.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../../core/network/backend_api_client.dart';
import '../../../dashboard/providers.dart';

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

  bool get isValid =>
      title.trim().isNotEmpty && classId != null && maxScore > 0;

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
  AssignmentFormController(this._ref, this._keepPending)
      : super(AssignmentFormState());
  final Ref _ref;
  final void Function() Function() _keepPending;
  void Function()? _releasePending;
  AssignmentDraft? _pendingSaveDraft;
  String? _pendingSaveFingerprint;
  bool _hasUncertainSave = false;

  void hydrate(Assignment a) {
    if (_pendingSaveDraft != null && state.assignmentId == a.id) return;
    _pendingSaveDraft = null;
    _pendingSaveFingerprint = null;
    _hasUncertainSave = false;
    _releasePending?.call();
    _releasePending = null;
    state = AssignmentFormState(
      assignmentId: a.id,
      classId: a.classId,
      title: a.title,
      description: a.description ?? '',
      instructions: a.instructions ?? '',
      kind: a.kind,
      dueAt: a.dueAt ?? DateTime.now().add(const Duration(days: 1)),
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
      state = state.copyWith(uploading: false, error: 'No se pudo subir: $e');
    }
  }

  void removeAttachment(String id) {
    state = state.copyWith(
      attachments: state.attachments.where((a) => a.id != id).toList(),
    );
  }

  String _saveFingerprint() => jsonEncode([
        state.assignmentId,
        state.classId,
        state.title.trim(),
        state.description.trim(),
        state.instructions.trim(),
        state.kind.name,
        state.dueAt.toUtc().toIso8601String(),
        state.maxScore,
        state.allowLate,
        state.published,
        state.attachments.map((a) => a.id).toList()..sort(),
      ]);

  Future<Assignment?> save() async {
    if (state.saving) return null;
    if (!state.isValid) {
      state = state.copyWith(error: 'Completa título, clase y puntaje.');
      return null;
    }
    state = state.copyWith(saving: true, clearError: true);
    try {
      final repo = _ref.read(assignmentRepositoryProvider);
      // Resolve the original attempt before sending edits with another key.
      // Otherwise an unconfirmed creation could become a duplicate task.
      if (_pendingSaveDraft != null &&
          _pendingSaveFingerprint != _saveFingerprint()) {
        final confirmed = await repo.upsertAssignment(_pendingSaveDraft!);
        if (!mounted) return null;
        state = state.copyWith(assignmentId: confirmed.id);
        _pendingSaveDraft = null;
        _pendingSaveFingerprint = null;
        _hasUncertainSave = false;
      }
      if (_pendingSaveDraft == null) {
        _pendingSaveFingerprint = _saveFingerprint();
        _pendingSaveDraft = AssignmentDraft(
          assignmentId: state.assignmentId,
          idempotencyKey: const Uuid().v4(),
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
        );
      }
      _releasePending ??= _keepPending();
      final created = await repo.upsertAssignment(_pendingSaveDraft!);
      if (!mounted) return null;
      _ref.invalidate(teacherDashboardProvider);
      _pendingSaveDraft = null;
      _pendingSaveFingerprint = null;
      _hasUncertainSave = false;
      state = state.copyWith(saving: false, assignmentId: created.id);
      _releasePending?.call();
      _releasePending = null;
      return created;
    } catch (e) {
      final rejected = e is BackendApiException &&
          !e.retryable &&
          e.statusCode != null &&
          e.statusCode! >= 400 &&
          e.statusCode! < 500 &&
          e.statusCode != 408;
      if (rejected && !_hasUncertainSave) {
        _pendingSaveDraft = null;
        _pendingSaveFingerprint = null;
        _releasePending?.call();
        _releasePending = null;
      } else {
        _hasUncertainSave = true;
      }
      if (mounted) {
        state = state.copyWith(saving: false, error: 'No se pudo guardar: $e');
      }
      return null;
    }
  }
}

final assignmentFormControllerProvider = StateNotifierProvider.autoDispose<
    AssignmentFormController, AssignmentFormState>((ref) {
  ref.watch(authControllerProvider.select((state) => state.user?.id));
  return AssignmentFormController(ref, () {
    final link = ref.keepAlive();
    return link.close;
  });
});
