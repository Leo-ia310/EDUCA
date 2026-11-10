import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../data/originality_report.dart';
import '../controllers/assignment_detail_controller.dart';
import '../controllers/originality_controller.dart';
import '../widgets/originality_widgets.dart';

/// Detalle de coincidencias textuales de una entrega (solo docente).
/// Móvil primero: una columna con el resultado, la fuente y la evidencia bajo
/// demanda. No muestra «porcentaje de copia» ni propone notas.
class OriginalityDetailScreen extends ConsumerWidget {
  const OriginalityDetailScreen({
    super.key,
    required this.assignmentId,
    required this.submissionId,
  });
  final String assignmentId, submissionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (assignmentId: assignmentId, submissionId: submissionId);
    final state = ref.watch(originalityReportProvider(args));
    final controller = ref.read(originalityReportProvider(args).notifier);
    final studentName = ref
        .watch(submissionsForAssignmentProvider(assignmentId))
        .valueOrNull
        ?.where((s) => s.id == submissionId)
        .map((s) => s.studentName)
        .firstOrNull;
    final palette = context.palette;

    Widget body;
    if (state.denied) {
      body = const _Message(
        icon: Icons.lock_outline_rounded,
        title: 'Ya no tienes acceso a este análisis',
        text:
            'Tus permisos en esta clase cambiaron o la entrega ya no está disponible.',
      );
    } else if (state.report == null && state.busy) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (state.report == null) {
      body = _Message(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudo consultar el análisis',
        text:
            'La entrega sigue siendo válida. Puedes volver a intentarlo en unos segundos.',
        action: FilledButton.icon(
          onPressed: controller.load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
        ),
      );
    } else {
      final report = state.report!;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.failed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'No se pudo actualizar; se muestra la última información.',
                style: context.textTheme.bodySmall
                    ?.copyWith(color: palette.warning),
              ),
            ),
          if (report.documents.isEmpty)
            const _Message(
              icon: Icons.hourglass_top_rounded,
              title: 'Análisis pendiente',
              text:
                  'La entrega aún no se registra para análisis o no tiene contenido analizable. Se actualizará sola.',
            ),
          for (final doc in report.documents) ...[
            _DocumentSection(
              doc: doc,
              studentName: studentName,
              busy: state.busy,
              showEvidence: state.evidence,
              onEvidence: controller.showEvidence,
              onRetry: () => controller.load(retry: true),
            ),
            const SizedBox(height: 16),
          ],
          OriginalityNoticeBox(text: report.notice),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'La cobertura mide qué parte de las palabras comparables de esta '
              'entrega aparece en la fuente. Al invertir la comparación puede '
              'ser distinta. El orden de entrega orienta, pero no prueba quién '
              'copió a quién.',
              style: context.textTheme.bodySmall
                  ?.copyWith(color: palette.textMuted),
            ),
          ),
        ],
      );
    }

    return OriginalityAuthGuard(
      child: StudentDetailScaffold(
        title: 'Coincidencias textuales',
        bottomNav: false,
        onRefresh: () => controller.load(),
        topActions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: state.busy ? null : () => controller.load(),
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (studentName != null) ...[
              Text(
                studentName,
                style: context.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                'Análisis de la entrega',
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: 12),
            ],
            if (state.busy && state.report != null)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            body,
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
  });
  final IconData icon;
  final String title, text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DepthCard(
      soft: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(icon, size: 36, color: palette.textMuted),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            textAlign: TextAlign.center,
            style:
                context.textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

final _dateFmt = DateFormat('d MMM yyyy, HH:mm', 'es');

String _gap(Duration d) {
  final m = d.inMinutes.abs();
  if (m < 1) return 'menos de 1 minuto';
  if (m < 60) return '$m min';
  final h = d.inHours.abs();
  if (h < 48) return h == 1 ? '1 hora' : '$h horas';
  final days = d.inDays.abs();
  return '$days días';
}

class _DocumentSection extends StatelessWidget {
  const _DocumentSection({
    required this.doc,
    required this.studentName,
    required this.busy,
    required this.showEvidence,
    required this.onEvidence,
    required this.onRetry,
  });
  final OriginalityDocument doc;
  final String? studentName;
  final bool busy, showEvidence;
  final Future<void> Function() onEvidence;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = doc.status;
    final (sBg, sFg) = originalityToneColors(palette, status.tone);
    final coverage = doc.coverage;
    final match = doc.match;
    return DepthCard(
      soft: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_rounded,
                size: 20,
                color: palette.accentDeep,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doc.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Tag(
                icon: originalityStatusIcon(doc.state, compared: doc.compared),
                text: status.label,
                bg: sBg,
                fg: sFg,
              ),
              if (doc.preliminary && doc.state == 'completed')
                _Tag(
                  icon: Icons.update_rounded,
                  text: 'Preliminar',
                  bg: palette.surfaceAlt,
                  fg: palette.textMuted,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (coverage != null)
            _CoverageHero(coverage: coverage)
          else
            Text(
              status.hint,
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: palette.textMuted),
            ),
          if (doc.state == 'failed') ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : onRetry,
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: const Text('Reintentar análisis'),
            ),
          ],
          if (doc.preliminary && doc.state == 'completed') ...[
            const SizedBox(height: 10),
            Text(
              'Reporte preliminar: puede recibir nuevas coincidencias cuando '
              'lleguen más entregas.',
              style: context.textTheme.bodySmall
                  ?.copyWith(color: palette.textMuted),
            ),
          ],
          if (match != null) ...[
            const SizedBox(height: 16),
            _SourceCard(doc: doc, match: match, studentName: studentName),
            const SizedBox(height: 16),
            _Evidence(
              match: match,
              loading: busy && showEvidence && !match.hasEvidence,
              onRequest: onEvidence,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            [
              'Entregado ${_dateFmt.format(doc.submittedAt.toLocal())}',
              if (doc.processedAt != null)
                'analizado ${_dateFmt.format(doc.processedAt!.toLocal())}',
              if (doc.algorithmVersion != null)
                'algoritmo ${doc.algorithmVersion}',
            ].join(' · '),
            style: context.textTheme.labelSmall
                ?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.icon,
    required this.text,
    required this.bg,
    required this.fg,
  });
  final IconData icon;
  final String text;
  final Color bg, fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                    ?.copyWith(color: fg, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
}

class _CoverageHero extends StatelessWidget {
  const _CoverageHero({required this.coverage});
  final double coverage;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final band = OriginalityBand.of(coverage);
    final color = originalityBandColor(palette, band);
    return Semantics(
      label:
          'Coincidencia textual máxima ${coverage.toStringAsFixed(1)} por ciento',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: (coverage / 100).clamp(0, 1),
                      strokeWidth: 9,
                      strokeCap: StrokeCap.round,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.18),
                    ),
                  ),
                  Text(
                    formatCoverage(coverage),
                    style: context.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Coincidencia máxima ${band.label.toLowerCase()}',
                    style: context.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'del texto comparable de esta entrega aparece en el '
                    'documento fuente con mayor coincidencia.',
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Comparación en dos columnas: esta entrega frente a la fuente.
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.doc,
    required this.match,
    required this.studentName,
  });
  final OriginalityDocument doc;
  final OriginalityMatch match;
  final String? studentName;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final diff = match.sourceSubmittedAt.difference(doc.submittedAt);
    final order = diff.inSeconds.abs() < 60
        ? 'Ambas se entregaron casi al mismo tiempo.'
        : diff.isNegative
            ? 'La fuente se entregó ${_gap(diff)} antes.'
            : 'La fuente se entregó ${_gap(diff)} después.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _VersusTile(
                label: 'Esta entrega',
                name: studentName ?? 'Estudiante',
                file: doc.name,
                at: doc.submittedAt,
                highlight: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 30),
              child: Icon(
                Icons.compare_arrows_rounded,
                color: palette.textMuted,
              ),
            ),
            Expanded(
              child: _VersusTile(
                label: 'Fuente',
                name: match.sourceStudent,
                file: match.sourceName,
                at: match.sourceSubmittedAt,
                highlight: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '$order El orden no prueba quién copió.',
          style:
              context.textTheme.bodySmall?.copyWith(color: palette.textMuted),
        ),
        if (match.binaryIdentical || match.textIdentical) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (match.binaryIdentical)
                _Tag(
                  icon: Icons.fingerprint_rounded,
                  text: 'Archivo idéntico (SHA-256)',
                  bg: palette.warning.withValues(alpha: 0.18),
                  fg: palette.warning,
                ),
              if (match.textIdentical)
                _Tag(
                  icon: Icons.text_snippet_rounded,
                  text: 'Texto normalizado idéntico',
                  bg: palette.warning.withValues(alpha: 0.18),
                  fg: palette.warning,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _VersusTile extends StatelessWidget {
  const _VersusTile({
    required this.label,
    required this.name,
    required this.file,
    required this.at,
    required this.highlight,
  });
  final String label, name, file;
  final DateTime at;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? palette.accentSoft.withValues(alpha: 0.7)
            : palette.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: context.textTheme.labelSmall?.copyWith(
              color: highlight ? palette.accentDeep : palette.textMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            file,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                context.textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: palette.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  DateFormat('d MMM, HH:mm', 'es').format(at.toLocal()),
                  style: context.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _Side { current, source }

/// Evidencia bajo demanda. Los tramos de cada documento se listan por
/// separado: no están emparejados uno a uno entre sí.
class _Evidence extends StatefulWidget {
  const _Evidence({
    required this.match,
    required this.loading,
    required this.onRequest,
  });
  final OriginalityMatch match;
  final bool loading;
  final Future<void> Function() onRequest;

  @override
  State<_Evidence> createState() => _EvidenceState();
}

class _EvidenceState extends State<_Evidence> {
  _Side _side = _Side.current;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = widget.match;
    if (!m.hasEvidence) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: widget.loading ? null : widget.onRequest,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
          icon: widget.loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.manage_search_rounded, size: 20),
          label: const Text('Ver fragmentos coincidentes'),
        ),
      );
    }
    final fragments = _side == _Side.current ? m.fragments : m.sourceFragments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Fragmentos coincidentes'),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_Side>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _Side.current,
                label: Text('Esta entrega (${m.fragments.length})'),
              ),
              ButtonSegment(
                value: _Side.source,
                label: Text('Fuente (${m.sourceFragments.length})'),
              ),
            ],
            selected: {_side},
            onSelectionChanged: (v) => setState(() => _side = v.first),
          ),
        ),
        const SizedBox(height: 10),
        if (fragments.isEmpty)
          Text(
            'Sin fragmentos para mostrar de este lado.',
            style:
                context.textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        for (var i = 0; i < fragments.length; i++)
          _FragmentCard(index: i + 1, fragment: fragments[i]),
        const SizedBox(height: 4),
        Text(
          'Vista limitada a 10 fragmentos por documento y hasta 1.500 '
          'caracteres por fragmento. Cada lado lista sus propios tramos.',
          style:
              context.textTheme.labelSmall?.copyWith(color: palette.textMuted),
        ),
      ],
    );
  }
}

class _FragmentCard extends StatelessWidget {
  const _FragmentCard({required this.index, required this.fragment});
  final int index;
  final OriginalityFragment fragment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: palette.accentSoft.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border(left: BorderSide(color: palette.accent, width: 4)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tramo $index',
            style: context.textTheme.labelSmall?.copyWith(
              color: palette.accentDeep,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            fragment.text,
            style: context.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}
