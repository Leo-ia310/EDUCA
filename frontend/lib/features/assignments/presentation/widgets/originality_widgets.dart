import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/originality_report.dart';
import '../../data/originality_summary.dart';

/// Aviso obligatorio (especificación §6). Siempre visible en las vistas de
/// Originality. Nunca se habla de «porcentaje de copia» ni de notas.
const originalityNotice =
    'Este resultado es orientativo; una coincidencia textual no demuestra '
    'plagio ni identifica al autor original. La valoración corresponde al docente.';

/// Colores (fondo, tinta) de cada estado. Sin rojo salvo para errores técnicos.
(Color, Color) originalityToneColors(AppPalette p, OriginalityTone tone) =>
    switch (tone) {
      OriginalityTone.neutral => (p.surfaceAlt, p.textMuted),
      OriginalityTone.progress => (p.info.withValues(alpha: 0.16), p.info),
      OriginalityTone.success => (p.accentSoft, p.accentDeep),
      OriginalityTone.caution => (p.warning.withValues(alpha: 0.18), p.warning),
      OriginalityTone.error => (p.danger.withValues(alpha: 0.14), p.danger),
    };

/// Color de énfasis de una banda de cobertura: azul de marca, ámbar si es alta.
Color originalityBandColor(AppPalette p, OriginalityBand band) =>
    switch (band) {
      OriginalityBand.minimal => p.textMuted,
      OriginalityBand.low => p.accent,
      OriginalityBand.moderate => p.accentDeep,
      OriginalityBand.high => p.warning,
    };

IconData originalityStatusIcon(String state, {required bool compared}) =>
    switch (state) {
      'queued' => Icons.hourglass_top_rounded,
      'processing' => Icons.sync_rounded,
      'failed' => Icons.error_outline_rounded,
      'insufficient_text' => Icons.short_text_rounded,
      'unsupported_format' => Icons.block_rounded,
      'completed' when !compared => Icons.people_outline_rounded,
      _ => Icons.find_in_page_rounded,
    };

String formatCoverage(double c) =>
    c == c.roundToDouble() ? '${c.round()} %' : '${c.toStringAsFixed(1)} %';

/// Pastilla compacta con el estado o el porcentaje máximo de una entrega.
class OriginalityPill extends StatelessWidget {
  const OriginalityPill({super.key, required this.item});
  final OriginalityItem item;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final coverage = item.shownCoverage;
    final band = item.band;
    final status = item.status;
    final (bg, fg) = coverage != null && band != null
        ? (
            originalityBandColor(palette, band).withValues(alpha: 0.16),
            context.textTheme.labelLarge?.color ?? palette.accentDeep,
          )
        : originalityToneColors(palette, status.tone);
    final text = coverage != null ? formatCoverage(coverage) : status.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (coverage != null && band != null)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: originalityBandColor(palette, band),
                shape: BoxShape.circle,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Icon(
                originalityStatusIcon(item.state, compared: item.compared),
                size: 14,
                color: fg,
              ),
            ),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila que se inserta en la tarjeta de cada entrega: lleva al detalle.
class OriginalityRow extends StatelessWidget {
  const OriginalityRow({
    super.key,
    required this.assignmentId,
    required this.submissionId,
    required this.item,
    this.loading = false,
  });
  final String assignmentId, submissionId;
  final OriginalityItem? item;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final item = this.item;
    final band = item?.band;
    return Material(
      color: palette.accentSoft.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: () => context.push(
          '${Routes.assignments}/$assignmentId/originality/$submissionId',
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Icon(
                Icons.find_in_page_rounded,
                size: 20,
                color: palette.accentDeep,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Coincidencias',
                      style: context.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      item == null
                          ? (loading ? 'Consultando…' : 'Ver análisis')
                          : band != null
                              ? 'Máxima ${band.label.toLowerCase()}'
                              : item.status.hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
              ),
              if (item != null) ...[
                const SizedBox(width: 8),
                Flexible(child: OriginalityPill(item: item)),
              ],
              Icon(Icons.chevron_right_rounded, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviso legal con ícono; siempre visible en detalle y resumen.
class OriginalityNoticeBox extends StatelessWidget {
  const OriginalityNoticeBox({super.key, this.text});
  final String? text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: palette.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text ?? originalityNotice,
              style: context.textTheme.bodySmall
                  ?.copyWith(color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cierra la pantalla si cambia la sesión (usuario, institución o rol): la
/// evidencia de otros estudiantes no debe sobrevivir a un cambio de contexto.
class OriginalityAuthGuard extends ConsumerWidget {
  const OriginalityAuthGuard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(
      authControllerProvider.select(
        (s) => (s.user?.id, s.user?.institutionId, s.user?.activeRole),
      ),
      (previous, next) {
        if (previous == next) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(Routes.assignments);
        }
      },
    );
    return child;
  }
}
