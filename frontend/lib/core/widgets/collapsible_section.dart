import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'depth_card.dart';

/// Sección desplegable encerrada en una tarjeta: el encabezado (acento +
/// título + conteo + chevron) siempre visible; al tocarlo, la misma tarjeta
/// se expande mostrando el resto de tarjetas dentro. Usada en paneles con
/// varios grupos (p. ej. Mis tareas).
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
    return DepthCard(
      soft: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.lg),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: palette.accentDeep,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
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
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: context.motion(AppMotion.fast),
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          color: palette.textMuted,),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: context.motion(AppMotion.base),
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widget.children,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
