import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../data/dashboard_data.dart';
import '../../providers.dart';
import '../widgets/student_chrome.dart';

/// Un maestro del alumno (agregado desde sus materias).
class Teacher {
  Teacher(this.name, this.color);
  final String name;
  final Color color;
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
      () => Teacher(s.teacher, s.color ?? subjectColor(s.name)),
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
            _TeacherCard(teacher: teachers[i]),
          ],
        ],
      ),
    );
  }
}

class _TeacherCard extends StatelessWidget {
  const _TeacherCard({required this.teacher});
  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(teacher.color);
    final initials = teacher.initials;

    return DepthCard(
      color: s.surface,
      accent: s.vivid,
      soft: true,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
            child: Text(
              initials,
              style: context.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
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
                  style: context.textTheme.bodySmall?.copyWith(color: s.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: () => context.go(Routes.chat),
            tooltip: 'Chatear con ${teacher.name}',
            icon: Icon(Icons.chat_bubble_rounded, color: s.vivid),
            style: IconButton.styleFrom(
              backgroundColor: s.vivid.withValues(alpha: 0.16),
            ),
          ),
        ],
      ),
    );
  }
}
