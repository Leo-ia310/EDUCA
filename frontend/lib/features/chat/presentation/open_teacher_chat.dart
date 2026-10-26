import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/env.dart';
import '../../../core/routing/route_paths.dart';
import '../providers.dart';

/// Nombre sin título ("Prof."/"Profa."/"Profe.") ni mayúsculas/acentos, para comparar.
String _normalized(String name) {
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  var out = name.toLowerCase().trim();
  for (var i = 0; i < from.length; i++) {
    out = out.replaceAll(from[i], to[i]);
  }
  return out.replaceFirst(RegExp(r'^prof(e|a|esor|esora)?\.?\s+'), '');
}

/// Abre directamente la conversación con un maestro. Si no se conoce su id de
/// usuario lo busca entre los contactos por nombre; solo si no lo encuentra
/// abre el selector de contactos.
Future<void> openTeacherChat(
  BuildContext context,
  WidgetRef ref, {
  required String teacherName,
  String? teacherUserId,
}) async {
  final repo = ref.read(chatRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  try {
    var id = teacherUserId;
    if (id == null && Env.isDemoMode) {
      final slug =
          teacherName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      id = 'u-teacher-$slug';
    }
    if (id == null) {
      final wanted = _normalized(teacherName);
      final contacts = await repo.discoverableContacts(query: teacherName);
      final matches = contacts.where((c) => _normalized(c.name) == wanted);
      final teacher = matches.where((c) => c.role == 'teacher');
      id = (teacher.isNotEmpty ? teacher.first : matches.firstOrNull)?.userId;
    }
    if (id == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No encontramos al maestro: elige el contacto a mano.'),
        ),
      );
      router.push(Routes.chatNew);
      return;
    }
    final conv = await repo.ensureIndividual(
      otherUserId: id,
      otherName: teacherName,
      otherRole: 'teacher',
    );
    router.push('${Routes.chat}/${conv.id}');
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('No se pudo abrir el chat: $e')),
    );
  }
}
