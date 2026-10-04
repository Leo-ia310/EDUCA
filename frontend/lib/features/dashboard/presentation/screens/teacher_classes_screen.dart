import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/entrance.dart';
import '../../../../core/widgets/open_card.dart';
import '../../data/dashboard_data.dart';
import '../../data/mock_dashboard_data.dart';
import '../../providers.dart';
import '../widgets/student_chrome.dart';
import 'class_detail_screen.dart';

/// Panel "Mis clases" del docente: una tarjeta por cada clase asignada.
class TeacherClassesScreen extends ConsumerWidget {
  const TeacherClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(teacherDashboardProvider).valueOrNull ??
        TeacherDashboardData.mock();
    final classes = data.myClasses;

    return StudentDetailScaffold(
      title: 'Mis clases',
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      child: SafeArea(
        bottom: false,
        child: classes.isEmpty
            ? const EmptyState(
                icon: Icons.class_rounded,
                title: 'Sin clases asignadas',
                subtitle: 'Aún no tienes clases asignadas.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
                children: [
                  for (final (i, c) in classes.indexed)
                    entranceItem(
                      context,
                      i,
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OpenCard(
                          borderRadius: Radii.lg,
                          open: (context) => ClassDetailScreen(teacherClass: c),
                          closed: (context, open) =>
                              _ClassTile(teacherClass: c, onTap: open),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ClassTile extends StatelessWidget {
  const _ClassTile({required this.teacherClass, required this.onTap});

  final TeacherClass teacherClass;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subjectColor(teacherClass.name));
    final ink = Brutal.ink(context);
    return BrutalBox(
      onTap: onTap,
      color: s.surface,
      radius: Radii.lg,
      clip: true,
      child: Stack(
        children: [
          Positioned(
            right: -14,
            bottom: -14,
            child: Icon(
              teacherClass.icon,
              size: 110,
              color: s.vivid.withValues(alpha: 0.16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: s.vivid,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: ink, width: Brutal.border),
                  ),
                  child: Icon(teacherClass.icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        teacherClass.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleMedium?.copyWith(
                          color: s.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        teacherClass.room,
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: s.inkMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: ink, width: Brutal.border),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.black,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
