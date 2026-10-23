import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/backend_api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../data/originality_report.dart';
import '../../../auth/presentation/auth_controller.dart';

/// A single lazy report per opened delivery; polling stops when the dialog closes.
class OriginalityButton extends ConsumerWidget {
  const OriginalityButton({super.key, required this.submissionId});
  final String submissionId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(backendApiClientProvider) == null) {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      icon: const Icon(Icons.find_in_page_rounded),
      label: const Text('Coincidencias textuales'),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: OriginalityPanel(submissionId: submissionId),
          ),
        ),
      ),
    );
  }
}

class OriginalityPanel extends ConsumerStatefulWidget {
  const OriginalityPanel({super.key, required this.submissionId});
  final String submissionId;
  @override
  ConsumerState<OriginalityPanel> createState() => _OriginalityPanelState();
}

class _OriginalityPanelState extends ConsumerState<OriginalityPanel> {
  OriginalityReport? report;
  bool busy = false, failed = false;
  int delay = 5;
  Timer? timer;
  String get path =>
      '/assignments/submissions/${widget.submissionId}/originality';
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load({bool retry = false}) async {
    if (busy) return;
    timer?.cancel();
    setState(() => busy = true);
    try {
      final api = ref.read(backendApiClientProvider);
      if (api == null) throw StateError('Sesión no disponible');
      if (retry) await api.post('$path/retry', data: <String, dynamic>{});
      final data = await api.get(path, queryParameters: {'evidence': 'true'});
      if (!mounted) return;
      setState(() {
        report =
            OriginalityReport.fromJson(Map<String, dynamic>.from(data as Map));
        failed = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        failed = true;
        if (error is BackendApiException &&
            [401, 403, 404].contains(error.statusCode)) {
          report = null;
        }
      });
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (report?.pending ?? false) {
          timer = Timer(Duration(seconds: delay), () => unawaited(load()));
          delay = math.min(delay * 2, 60);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
        authControllerProvider.select(
          (state) => (
            state.user?.id,
            state.user?.institutionId,
            state.user?.activeRole
          ),
        ), (previous, next) {
      if (previous != next) {
        timer?.cancel();
        Navigator.of(context).pop();
      }
    });
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Nivra Originality')),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: busy ? null : () => load(),
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
          if (failed)
            const Text(
              'No se pudo consultar el análisis. Puedes actualizar para reintentar.',
            ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (report != null && report!.documents.isEmpty)
                    const Text(
                      'Pendiente de análisis o sin contenido analizable.',
                    ),
                  for (final doc
                      in report?.documents ?? <OriginalityDocument>[]) ...[
                    const SizedBox(height: 12),
                    _DocumentCard(doc: doc),
                    if (doc.state == 'failed')
                      TextButton(
                        onPressed: busy ? null : () => load(retry: true),
                        child: const Text('Reintentar análisis'),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    report?.notice ??
                        'Este resultado es orientativo; una coincidencia textual no demuestra plagio ni identifica al autor original. La valoración corresponde al docente.',
                    style: context.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'La cobertura mide palabras coincidentes del documento consultado. Puede ser diferente al invertir la comparación. El orden de entrega no identifica al autor original.',
                    style: context.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.doc});
  final OriginalityDocument doc;
  @override
  Widget build(BuildContext context) {
    final match = doc.match, coverage = doc.coverage;
    final fmt = DateFormat('d MMM yyyy, HH:mm', 'es');
    return DepthCard(
      soft: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(doc.name, style: context.textTheme.titleSmall),
          Text(doc.label),
          Text(
            'Entrega: ${fmt.format(doc.submittedAt.toLocal())}',
            style: context.textTheme.bodySmall,
          ),
          if (doc.processedAt != null)
            Text(
              'Analizado: ${fmt.format(doc.processedAt!.toLocal())}',
              style: context.textTheme.bodySmall,
            ),
          if (doc.preliminary)
            const Text(
              'Reporte preliminar; puede recibir nuevas coincidencias.',
            ),
          if (coverage != null) ...[
            const SizedBox(height: 8),
            Text(
              '${coverage.toStringAsFixed(1)} % de coincidencia textual máxima',
            ),
            Semantics(
              label:
                  'Cobertura textual ${coverage.toStringAsFixed(1)} por ciento',
              child: LinearProgressIndicator(
                value: (coverage / 100).clamp(0, 1),
                color: context.palette.accent,
              ),
            ),
          ],
          if (match != null) ...[
            const SizedBox(height: 8),
            Text('Fuente: ${match.sourceName} · ${match.sourceStudent}'),
            Text(
              'Entrega fuente: ${fmt.format(match.sourceSubmittedAt.toLocal())}',
              style: context.textTheme.bodySmall,
            ),
            if (match.binaryIdentical) const Text('Archivo idéntico (SHA-256)'),
            if (match.textIdentical)
              const Text('Texto académico normalizado idéntico'),
            if (match.fragments.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Ver fragmentos coincidentes'),
                children: [
                  const Text('Documento consultado'),
                  for (final text in match.fragments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SelectableText(text),
                    ),
                  const Text('Documento fuente'),
                  for (final text in match.sourceFragments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SelectableText(text),
                    ),
                  const Text(
                    'Vista limitada a 10 fragmentos por documento; hasta 1500 caracteres por fragmento.',
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
