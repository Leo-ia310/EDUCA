import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/entrance.dart';
import '../../../chat/providers.dart';
import '../../data/dashboard_data.dart';
import '../../data/mock_dashboard_data.dart';
import '../../providers.dart';
import '../widgets/student_chrome.dart';
import 'parent_children_screen.dart';

/// Panel "Maestros" del padre: los docentes de cada materia del hijo
/// seleccionado en "Mis hijos", con acceso directo al chat con cada uno.
class ParentTeachersScreen extends ConsumerWidget {
  const ParentTeachersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(parentDashboardProvider).valueOrNull ??
        ParentDashboardData.mock();
    final kids = data.children;
    final child =
        kids[ref.watch(selectedChildIndexProvider).clamp(0, kids.length - 1)];
    final subjects = child.subjects.isEmpty ? data.subjects : child.subjects;

    return StudentDetailScaffold(
      title: 'Maestros de ${child.name}',
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, s) in subjects.indexed)
            entranceItem(
              context,
              i,
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TeacherRow(item: s),
              ),
            ),
        ],
      ),
    );
  }
}

class _TeacherRow extends ConsumerWidget {
  const _TeacherRow({required this.item});
  final ParentSubject item;

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    final id = item.teacherUserId;
    if (id == null) {
      context.push(Routes.chatNew);
      return;
    }
    final conv = await ref.read(chatRepositoryProvider).ensureIndividual(
          otherUserId: id,
          otherName: item.teacher,
          otherRole: 'teacher',
        );
    if (!context.mounted) return;
    context.push('${Routes.chat}/${conv.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.pastel(subjectColor(item.name));
    final ink = Brutal.ink(context);
    return BrutalBox(
      color: s.surface,
      radius: Radii.md,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: s.vivid,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: ink, width: Brutal.border),
            ),
            // Ícono de perfil del maestro.
            child: const Icon(
              Icons.account_circle_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.teacher,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall?.copyWith(
                    color: s.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      context.textTheme.bodySmall?.copyWith(color: s.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _openChat(context, ref),
            child: Container(
              width: 38,
              height: 38,
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
          ),
        ],
      ),
    );
  }
}
