import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'section_header.dart';

/// Sección desplegable: [SectionHeader] con chevron que expande/colapsa su
/// contenido. Usada en paneles con varios grupos (p. ej. Mis tareas).
class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    super.key,
    required this.title,
    required this.children,
    this.trailingCount,
    this.initiallyExpanded = true,
  });

  final String title;
  final List<Widget> children;

  /// Conteo opcional mostrado junto al título (p. ej. "3").
  final int? trailingCount;
  final bool initiallyExpanded;

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: SectionHeader(title: widget.title)),
                    if (widget.trailingCount != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2,),
                        decoration: BoxDecoration(
                          color: palette.accentSoft,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(
                          '${widget.trailingCount}',
                          style: context.textTheme.labelSmall?.copyWith(
                            color: palette.accentDeep,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: context.motion(AppMotion.fast),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    color: palette.textMuted,),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: context.motion(AppMotion.base),
          curve: AppMotion.standard,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.children,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
