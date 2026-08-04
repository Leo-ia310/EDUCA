import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../dashboard/data/mock_dashboard_data.dart';

/// Gestión de docentes: ver claustro y asignar clases. Alimenta los accesos
/// "Asignar Maestros" y "Gestionar" del panel admin.
class ManageTeachersScreen extends ConsumerStatefulWidget {
  const ManageTeachersScreen({super.key});

  @override
  ConsumerState<ManageTeachersScreen> createState() =>
      _ManageTeachersScreenState();
}

class _ManageTeachersScreenState extends ConsumerState<ManageTeachersScreen> {
  // Asignaciones hechas en la sesión: nombre docente -> clase.
  final Map<String, String> _assignments = {};

  static const _classes = <String>[
    'Matemáticas 4° A',
    'Matemáticas 4° B',
    'Ciencias 3° A',
    'Historia 5° A',
    'Literatura 2° B',
    'Biología 4° A',
  ];

  Future<void> _assign(AdminTeacher teacher) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Asignar clase a ${teacher.name}',
                  style: context.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              for (final c in _classes)
                ListTile(
                  leading: Icon(Icons.class_outlined,
                      color: context.palette.limeDeep),
                  title: Text(c),
                  trailing: _assignments[teacher.name] == c
                      ? Icon(Icons.check_circle,
                          color: context.palette.success)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(c),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected != null && mounted) {
      setState(() => _assignments[teacher.name] = selected);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${teacher.name} asignado a $selected.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Gestionar docentes'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            '${AdminMockData.teachers.length} docentes activos',
            style: context.textTheme.bodyMedium
                ?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
          for (final t in AdminMockData.teachers)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: EduCard(
                child: Row(
                  children: [
                    UserAvatar(name: t.name, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.name,
                            style: context.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(t.subject, style: context.textTheme.bodySmall),
                          if (_assignments[t.name] != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: palette.limeSoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _assignments[t.name]!,
                                style: context.textTheme.labelSmall?.copyWith(
                                  color: palette.limeDeep,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _assign(t),
                      // El tema fuerza minimumSize con ancho infinito (botones
                      // full-width); aquí es un botón compacto dentro de un Row,
                      // así que lo acotamos a su contenido.
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Text('Asignar'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
