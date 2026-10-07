import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/constants/env.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../chat/providers.dart';
import '../../data/dashboard_data.dart';
import '../../providers.dart';
import '../widgets/student_chrome.dart';

/// Un maestro del alumno (agregado desde sus materias).
class Teacher {
  Teacher(this.name, this.color, {this.icon = Icons.menu_book_rounded});
  final String name;
  final Color color;

  /// Ícono de la clase que imparte (la primera).
  final IconData icon;
  final List<String> subjects = [];

  /// Partes del nombre sin el título ("Prof."/"Profa."/"Profe.").
  List<String> get _parts {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty &&
        RegExp(r'^prof', caseSensitive: false).hasMatch(parts.first)) {
      return parts.length > 1 ? parts.sublist(1) : parts;
    }
    return parts;
  }

  String get firstName => _parts.isNotEmpty ? _parts.first : name;

  String get initials {
    final p = _parts;
    if (p.length >= 2 && p[0].isNotEmpty && p[1].isNotEmpty) {
      return '${p[0][0]}${p[1][0]}'.toUpperCase();
    }
    if (p.isNotEmpty && p[0].isNotEmpty) return p[0][0].toUpperCase();
    return '?';
  }
}

/// Deriva la lista de maestros a partir de las materias del alumno,
/// agrupando por nombre y juntando las materias que imparte.
List<Teacher> teachersFrom(StudentDashboardData data) {
  final byName = <String, Teacher>{};
  for (final s in data.subjects) {
    if (s.teacher.trim().isEmpty) continue;
    final t = byName.putIfAbsent(
      s.teacher,
      () => Teacher(
        s.teacher,
        s.color ?? subjectColor(s.name),
        icon: s.icon ?? Icons.menu_book_rounded,
      ),
    );
    t.subjects.add(s.name);
  }
  return byName.values.toList();
}

/// Pantalla "Mis maestros": tarjetas por profesor con sus materias y acceso
/// directo a chat.
class MyTeachersScreen extends ConsumerWidget {
  const MyTeachersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(studentDashboardProvider).valueOrNull ??
        StudentDashboardData.mock();
    final teachers = teachersFrom(data);

    return StudentDetailScaffold(
      title: 'Mis maestros',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < teachers.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            TeacherCard(teacher: teachers[i]),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta horizontal de un maestro: ícono de su clase, nombre + materias que
/// imparte. Al tocarla abre directamente el chat con ese maestro.
class TeacherCard extends ConsumerWidget {
  const TeacherCard({super.key, required this.teacher});
  final Teacher teacher;

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    // En demo se crea/abre la conversación con el maestro; sin backend de
    // contactos aún no hay id de usuario del maestro, así que se abre el
    // selector de contactos.
    if (!Env.isDemoMode) {
      context.push(Routes.chatNew);
      return;
    }
    final slug = teacher.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final conv = await ref.read(chatRepositoryProvider).ensureIndividual(
          otherUserId: 'u-teacher-$slug',
          otherName: teacher.name,
          otherRole: 'teacher',
        );
    if (!context.mounted) return;
    context.push('${Routes.chat}/${conv.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.pastel(teacher.color);
    final ink = Brutal.ink(context);

    return BrutalBox(
      onTap: () => _openChat(context, ref),
      color: s.surface,
      radius: Radii.lg,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.vivid,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: ink, width: Brutal.border),
            ),
            child: Icon(teacher.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  teacher.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleMedium
                      ?.copyWith(color: s.ink, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  teacher.subjects.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      context.textTheme.bodySmall?.copyWith(color: s.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: ink, width: Brutal.border),
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              color: Colors.black,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}
