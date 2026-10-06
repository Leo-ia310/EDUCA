import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../shared/models/app_role.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../data/school_directory.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/class_form.dart';
import '../widgets/person_form.dart';

const _groupColor = Color(0xFF33B7A0);

/// Salones / años: lista con su CRUD. Cada salón abre el detalle con la lista
/// de sus estudiantes y de sus clases.
class AdminGroupsScreen extends ConsumerWidget {
  const AdminGroupsScreen({super.key});

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref, {
    SchoolGroup? group,
  }) async {
    final c = TextEditingController(text: group?.name ?? '');
    final name = await showBrutalSheet<String>(
      context,
      title: group == null ? 'Nuevo salón' : 'Renombrar salón',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutalTextField(
            controller: c,
            label: 'Nombre (p. ej. 4° Grado A)',
            icon: Icons.meeting_room_rounded,
          ),
          const SizedBox(height: 16),
          Builder(
            builder: (ctx) => BrutalButton(
              expand: true,
              icon: Icons.save_rounded,
              label: group == null ? 'Crear' : 'Guardar',
              onTap: () {
                final v = c.text.trim();
                if (v.isNotEmpty) Navigator.of(ctx).pop(v);
              },
            ),
          ),
        ],
      ),
    );
    if (name == null) return;
    final store = ref.read(schoolDirectoryProvider.notifier);
    group == null ? store.addGroup(name) : store.renameGroup(group.id, name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dir = ref.watch(schoolDirectoryProvider);
    return StudentDetailScaffold(
      title: 'Salones y años',
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutalButton(
            expand: true,
            onTap: () => _editName(context, ref),
            icon: Icons.add_rounded,
            label: 'Nuevo salón',
          ),
          const SizedBox(height: 18),
          if (dir.groups.isEmpty)
            const EmptyState(
              icon: Icons.meeting_room_rounded,
              title: 'Sin salones',
              subtitle: 'Crea el primer salón o año.',
            )
          else
            for (final g in dir.groups)
              AdminTile(
                title: g.name,
                subtitle:
                    '${dir.studentsOfGroup(g.id).length} estudiantes · ${dir.classesOfGroup(g.id).length} clases',
                color: _groupColor,
                leadingIcon: Icons.meeting_room_rounded,
                trailing: _Chevron(),
                onTap: () => context.push('${Routes.adminGroups}/${g.id}'),
              ),
        ],
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: Brutal.ink(context), width: Brutal.border),
        ),
        child: const Icon(
          Icons.chevron_right_rounded,
          color: Colors.black,
          size: 24,
        ),
      );
}

/// Detalle de un salón: listas de estudiantes y de clases (editables).
class AdminGroupDetailScreen extends ConsumerWidget {
  const AdminGroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dir = ref.watch(schoolDirectoryProvider);
    final group = dir.group(groupId);
    if (group == null) {
      return const StudentDetailScaffold(
        title: 'Salón',
        bottomNav: false,
        child: EmptyState(
          icon: Icons.meeting_room_rounded,
          title: 'Salón no encontrado',
          subtitle: 'Es posible que haya sido eliminado.',
        ),
      );
    }
    final students = dir.studentsOfGroup(groupId)
      ..sort((a, b) => a.name.compareTo(b.name));
    final classes = dir.classesOfGroup(groupId);
    final store = ref.read(schoolDirectoryProvider.notifier);

    return StudentDetailScaffold(
      title: group.name,
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: BrutalButton(
                  onTap: () => const AdminGroupsScreen()
                      ._editName(context, ref, group: group),
                  icon: Icons.edit_rounded,
                  label: 'Renombrar',
                  color: context.palette.cardElevated,
                  foreground: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BrutalButton(
                  onTap: () async {
                    if (!await confirmDelete(
                      context,
                      'el salón ${group.name} (también sus clases)',
                    )) {
                      return;
                    }
                    store.removeGroup(groupId);
                    if (context.mounted) context.pop();
                  },
                  icon: Icons.delete_outline_rounded,
                  label: 'Eliminar',
                  color: context.palette.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(
                child: SectionHeader(title: 'Clases', accent: false),
              ),
              TextButton.icon(
                onPressed: () => showClassSheet(context, groupId: groupId),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nueva'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (classes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('Sin clases en este salón.'),
            ),
          for (final c in classes)
            AdminTile(
              title: c.subject,
              subtitle: dir.person(c.teacherId)?.name ?? 'Sin maestro asignado',
              caption: c.room.isEmpty ? null : c.room,
              color: subjectTone(c.subject),
              leadingIcon: Icons.menu_book_rounded,
              onTap: () => showClassSheet(context, existing: c),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: SectionHeader(title: 'Estudiantes', accent: false),
              ),
              TextButton.icon(
                onPressed: () =>
                    showPersonSheet(context, role: AppRole.student),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Nuevo'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (students.isEmpty) const Text('Sin estudiantes en este salón.'),
          for (final s in students)
            AdminTile(
              title: s.name,
              subtitle: s.email,
              color: roleColor(AppRole.student),
              leadingText: s.initials,
              dimmed: !s.active,
              onTap: () => showPersonSheet(context, existing: s),
            ),
        ],
      ),
    );
  }
}
