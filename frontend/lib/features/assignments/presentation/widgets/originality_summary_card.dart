import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../data/originality_report.dart';
import '../../data/originality_summary.dart';
import '../controllers/originality_controller.dart';
import 'originality_widgets.dart';

/// Resumen de Nivra Originality en el detalle de la tarea (perfil docente):
/// cuántas entregas se analizaron, cuántas esperan, cómo se reparten las
/// coincidencias y acceso a la plantilla de la actividad.
class OriginalitySummaryCard extends ConsumerWidget {
  const OriginalitySummaryCard({
    super.key,
    required this.assignmentId,
    required this.canEditTemplate,
  });
  final String assignmentId;
  final bool canEditTemplate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(originalityApiProvider) == null) {
      return const SizedBox.shrink();
    }
    final palette = context.palette;
    final summary = ref.watch(originalitySummaryProvider(assignmentId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Nivra Originality',
          action: summary.isLoading ? null : 'Actualizar',
          onActionTap: () => ref
              .read(originalitySummaryProvider(assignmentId).notifier)
              .refresh(),
        ),
        const SizedBox(height: 8),
        DepthCard(
          soft: true,
          padding: const EdgeInsets.all(16),
          child: summary.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No se pudo consultar el análisis de coincidencias.',
                  style: context.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Las entregas siguen siendo válidas. Puedes volver a intentarlo.',
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => ref
                      .read(originalitySummaryProvider(assignmentId).notifier)
                      .refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
            data: (s) => _Body(
              summary: s,
              assignmentId: assignmentId,
              canEditTemplate: canEditTemplate,
            ),
          ),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.summary,
    required this.assignmentId,
    required this.canEditTemplate,
  });
  final OriginalitySummary summary;
  final String assignmentId;
  final bool canEditTemplate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final s = summary;
    final total = s.eligible;
    final done = s.analyzedCount.clamp(0, total);
    final top = s.top;
    final bands = s.bands;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total == 0)
          Text(
            'Aún no hay entregas para analizar. Los resultados aparecerán '
            'cuando los estudiantes entreguen.',
            style: context.textTheme.bodyMedium
                ?.copyWith(color: palette.textMuted),
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$done de $total',
                      style: context.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'entregas analizadas',
                      style: context.textTheme.bodyMedium
                          ?.copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
              ),
              if (top != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatCoverage(top.shownCoverage!),
                        style: context.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: palette.accentDeep,
                        ),
                      ),
                      Text(
                        'mayor coincidencia',
                        textAlign: TextAlign.end,
                        style: context.textTheme.labelSmall
                            ?.copyWith(color: palette.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 8,
              color: palette.accent,
              backgroundColor: palette.accentSoft,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (s.pendingCount > 0)
                _Chip(
                  icon: Icons.hourglass_top_rounded,
                  text: '${s.pendingCount} en cola o procesando',
                  tone: OriginalityTone.progress,
                ),
              if (s.failedCount > 0)
                _Chip(
                  icon: Icons.error_outline_rounded,
                  text: '${s.failedCount} con error',
                  tone: OriginalityTone.error,
                ),
              if (s.count('insufficient_text') + s.count('unsupported_format') >
                  0)
                _Chip(
                  icon: Icons.short_text_rounded,
                  text:
                      '${s.count('insufficient_text') + s.count('unsupported_format')} sin texto analizable',
                  tone: OriginalityTone.caution,
                ),
              if (s.items.any((i) => i.binaryIdentical || i.textIdentical))
                _Chip(
                  icon: Icons.content_copy_rounded,
                  text:
                      '${s.items.where((i) => i.binaryIdentical || i.textIdentical).length} con contenido idéntico',
                  tone: OriginalityTone.caution,
                ),
            ],
          ),
          if (s.withPercentage > 0) ...[
            const SizedBox(height: 14),
            Text(
              'Reparto de la coincidencia máxima',
              style: context.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final b in OriginalityBand.values)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: b == OriginalityBand.high ? 0 : 8,
                      ),
                      child: _BandCell(band: b, count: bands[b] ?? 0),
                    ),
                  ),
              ],
            ),
          ],
          if (s.preliminary) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.update_rounded, size: 16, color: palette.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Resultado preliminar: puede cambiar cuando lleguen nuevas '
                    'entregas o termine el análisis.',
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: palette.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => context.push(
            '${Routes.assignments}/$assignmentId/originality/template',
          ),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: Icon(
            s.hasTemplate
                ? Icons.fact_check_rounded
                : Icons.playlist_remove_rounded,
            size: 18,
          ),
          label: Text(
            s.hasTemplate
                ? (canEditTemplate
                    ? 'Plantilla activa · editar'
                    : 'Plantilla activa')
                : (canEditTemplate
                    ? 'Agregar plantilla de exclusión'
                    : 'Ver plantilla de exclusión'),
          ),
        ),
        const SizedBox(height: 12),
        OriginalityNoticeBox(text: s.notice),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, required this.tone});
  final IconData icon;
  final String text;
  final OriginalityTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = originalityToneColors(context.palette, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: context.textTheme.labelMedium
                  ?.copyWith(color: fg, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _BandCell extends StatelessWidget {
  const _BandCell({required this.band, required this.count});
  final OriginalityBand band;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = originalityBandColor(palette, band);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: count == 0 ? 0.06 : 0.16),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: count == 0 ? palette.textMuted : null,
            ),
          ),
          Text(
            band.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelSmall
                ?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}
