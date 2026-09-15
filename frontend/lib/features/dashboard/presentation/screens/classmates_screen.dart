import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../data/mock_dashboard_data.dart';
import '../../domain/dashboard_models.dart';
import '../widgets/student_chrome.dart';

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
                    itemBuilder: (context, i) => _ClassmateRow(
                      classmate: filtered[i],
                      onTap: () => _showSummary(context, filtered[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showSummary(BuildContext context, Classmate c) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ClassmateSummary(classmate: c),
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

class _ClassmateSummary extends StatelessWidget {
  const _ClassmateSummary({required this.classmate});
  final Classmate classmate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Avatar(name: classmate.name, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        classmate.name,
                        style: context.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        classmate.grade,
                        style: TextStyle(color: palette.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _StatBox(
                    icon: Icons.event_available_rounded,
                    color: const Color(0xFF34C77A),
                    value: '${(classmate.attendanceRate * 100).round()}%',
                    label: 'Asistencia',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatBox(
                    icon: Icons.grade_rounded,
                    color: const Color(0xFF9A6BE0),
                    value: classmate.average.toStringAsFixed(1),
                    label: 'Promedio',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(color);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: s.vivid, size: 26),
          const SizedBox(height: 8),
          Text(
            value,
            style: context.textTheme.titleLarge
                ?.copyWith(color: s.ink, fontWeight: FontWeight.w800),
          ),
          Text(label, style: context.textTheme.bodySmall?.copyWith(color: s.inkMuted)),
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
