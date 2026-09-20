import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/entrance.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../data/mock_dashboard_data.dart';
import '../../domain/dashboard_models.dart';
import '../widgets/student_chrome.dart';
import 'classmate_profile_screen.dart';

/// Lista de compañeros del grado del estudiante. Barra de búsqueda + lista de
/// usuarios; al tocar uno se muestra un resumen (asistencia, promedio).
class ClassmatesScreen extends StatefulWidget {
  const ClassmatesScreen({super.key});

  @override
  State<ClassmatesScreen> createState() => _ClassmatesScreenState();
}

class _ClassmatesScreenState extends State<ClassmatesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const all = StudentMockData.classmateList;
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all.where((c) => c.name.toLowerCase().contains(q)).toList();

    return StudentDetailScaffold(
      title: 'Compañeros',
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar compañero',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Limpiar',
                        onPressed: () => setState(() => _query = ''),
                      ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'Sin resultados para "$_query"',
                      style: TextStyle(color: palette.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => entranceItem(
                      context,
                      i,
                      _ClassmateRow(
                        classmate: filtered[i],
                        onTap: () => _openProfile(context, filtered[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _openProfile(BuildContext context, Classmate c) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClassmateProfileScreen(classmate: c),
      ),
    );
  }
}

class _ClassmateRow extends StatelessWidget {
  const _ClassmateRow({required this.classmate, required this.onTap});
  final Classmate classmate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subjectColor(classmate.name));
    return DepthCard(
      color: s.surface,
      accent: s.vivid,
      soft: true,
      onTap: onTap,
      borderRadius: Radii.md,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _Avatar(name: classmate.name, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  classmate.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  classmate.grade,
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: s.inkMuted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: s.inkMuted),
        ],
      ),
    );
  }
}

/// Avatar circular con las iniciales sobre el color derivado del nombre.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(subjectColor(name));
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = (parts.length >= 2
            ? '${parts.first[0]}${parts[1][0]}'
            : name.isNotEmpty
                ? name[0]
                : '?')
        .toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: s.vivid, shape: BoxShape.circle),
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}
