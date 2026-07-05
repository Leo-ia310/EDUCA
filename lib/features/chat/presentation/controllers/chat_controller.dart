import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../assignments/providers.dart' show fileUploadServiceProvider;
import '../../domain/entities.dart';
import '../../providers.dart';

class ComposerState {
  const ComposerState({
    this.attachment,
    this.sending = false,
    this.uploading = false,
    this.error,
  });

  final MessageAttachment? attachment;
  final bool sending;
  final bool uploading;
  final String? error;

  ComposerState copyWith({
    MessageAttachment? attachment,
    bool? sending,
    bool? uploading,
    String? error,
    bool clearAttachment = false,
    bool clearError = false,
  }) {
    return ComposerState(
      attachment: clearAttachment ? null : (attachment ?? this.attachment),
      sending: sending ?? this.sending,
      uploading: uploading ?? this.uploading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ChatComposerController extends StateNotifier<ComposerState> {
  ChatComposerController(this._ref, this.conversationId)
      : super(const ComposerState()) {
    // Marcar como leído al abrir la conversación.
    _ref.read(chatRepositoryProvider).markAsRead(conversationId);
  }

  final Ref _ref;
  final String conversationId;

  Future<void> pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.path == null) return;
    state = state.copyWith(uploading: true, clearError: true);
    try {
      final uploader = _ref.read(fileUploadServiceProvider);
      final assignment = await uploader.upload(
        file: File(f.path!),
        folder: 'chat/$conversationId',
      );
      state = state.copyWith(
        attachment: MessageAttachment(
          id: assignment.id,
          name: assignment.name,
          url: assignment.url,
          sizeBytes: assignment.sizeBytes,
          mimeType: assignment.mimeType,
        ),
        uploading: false,
      );
    } catch (e) {
      state = state.copyWith(
          uploading: false, error: 'No se pudo adjuntar: $e');
    }
  }

  void clearAttachment() =>
      state = state.copyWith(clearAttachment: true);

  Future<void> send(String text) async {
    if (text.trim().isEmpty && state.attachment == null) return;
    state = state.copyWith(sending: true, clearError: true);
    try {
      await _ref.read(chatRepositoryProvider).sendMessage(
            conversationId: conversationId,
            content: text.trim().isEmpty ? null : text.trim(),
            attachment: state.attachment,
          );
      state = const ComposerState();
    } catch (e) {
      state = state.copyWith(sending: false, error: 'No se pudo enviar: $e');
    }
  }
}

final chatComposerProvider = StateNotifierProvider.autoDispose
    .family<ChatComposerController, ComposerState, String>((ref, convId) {
  return ChatComposerController(ref, convId);
});
