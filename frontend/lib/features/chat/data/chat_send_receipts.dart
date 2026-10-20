import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Only an account-scoped payload fingerprint and UUID are persisted, never text
/// or attachment URLs. Retrying identical unresolved content reuses its receipt.
class ChatSendReceipts {
  ChatSendReceipts(this.scope);
  final String scope;
  String slot(String conversationId, String? content, String? fileId) =>
      'chat_send_v1.${const Uuid().v5(Namespace.url.value, jsonEncode([
                scope,
                conversationId,
                content,
                fileId,
              ]),)}';
  Future<String> begin(String slot) async {
    final preferences = await SharedPreferences.getInstance();
    final previous = preferences.getString(slot);
    if (previous != null) return previous;
    final id = const Uuid().v4();
    if (!await preferences.setString(slot, id)) {
      throw StateError('No se pudo guardar la clave de reintento del mensaje.');
    }
    return id;
  }

  Future<void> confirm(String slot, String id) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getString(slot) == id && !await preferences.remove(slot)) {
      // Keep the operation unresolved: its next replay is safe even though the
      // server committed. Never reuse a completed key for a new identical text.
      throw StateError(
          'El mensaje se guardó; falta confirmar su clave local. Reintenta.',);
    }
  }
}
