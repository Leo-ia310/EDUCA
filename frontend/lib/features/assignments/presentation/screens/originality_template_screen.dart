import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../collaborations/providers.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../controllers/assignment_detail_controller.dart';
import '../controllers/originality_controller.dart';
import '../widgets/originality_widgets.dart';

/// Plantilla de exclusión de una actividad: texto común a todas las entregas
/// (portada, consigna, formato entregado) que no debe contar como coincidencia.
class OriginalityTemplateScreen extends ConsumerStatefulWidget {
  const OriginalityTemplateScreen({super.key, required this.assignmentId});
  final String assignmentId;

  @override
  ConsumerState<OriginalityTemplateScreen> createState() =>
      _OriginalityTemplateScreenState();
}

class _OriginalityTemplateScreenState
    extends ConsumerState<OriginalityTemplateScreen> {
  final _ctrl = TextEditingController();
  String _saved = '';
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _dirty => _ctrl.text.trim() != _saved.trim();

  Future<void> _save({bool clear = false}) async {
    final api = ref.read(originalityApiProvider);
    if (api == null) return;
    final text = clear ? '' : _ctrl.text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(clear ? 'Quitar plantilla' : 'Guardar y reanalizar'),
        content: const Text(
          'Se volverán a analizar todas las entregas de esta actividad con la '
          'nueva exclusión. Los resultados actuales se reemplazarán cuando '
          'termine el análisis. No cambia ninguna nota ni entrega.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final count = await api.saveTemplate(widget.assignmentId, text);
      if (!mounted) return;
      _saved = text;
      _ctrl.text = text;
      ref.invalidate(originalityTemplateProvider(widget.assignmentId));
      unawaited(
        ref
            .read(originalitySummaryProvider(widget.assignmentId).notifier)
            .refresh(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Plantilla guardada.'
                : 'Plantilla guardada. Reanalizando $count '
                    '${count == 1 ? 'documento' : 'documentos'}…',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar la plantilla.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final template =
        ref.watch(originalityTemplateProvider(widget.assignmentId));
    final assignment =
        ref.watch(assignmentByIdProvider(widget.assignmentId)).valueOrNull;
    final canEdit = assignment != null &&
        ref.watch(
          classPermissionProvider((assignment.classId, 'assignments.create')),
        );

    final data = template.valueOrNull;
    if (data != null && !_loaded) {
      _loaded = true;
      _saved = data.template;
      _ctrl.text = data.template;
    }

    return OriginalityAuthGuard(
      child: StudentDetailScaffold(
        title: 'Plantilla de exclusión',
        bottomNav: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DepthCard(
              soft: true,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.playlist_remove_rounded,
                        color: palette.accentDeep,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Texto que no cuenta como coincidencia',
                          style: context.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pega la portada, las preguntas o la plantilla que entregaste '
                    'a toda la clase. Las líneas de al menos 20 caracteres que '
                    'aparezcan idénticas en una entrega se excluyen del cálculo, '
                    'para que el contenido compartido no infle el porcentaje.',
                    style: context.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data == null
                        ? 'Además se excluyen automáticamente la descripción e '
                            'instrucciones de la tarea, las citas marcadas con «>» '
                            'y la sección de bibliografía.'
                        : 'Además ya se excluyen automáticamente '
                            '${data.instructionsLines} '
                            '${data.instructionsLines == 1 ? 'línea' : 'líneas'} '
                            'de la descripción e instrucciones de la tarea, las '
                            'citas marcadas con «>» y la sección de bibliografía.',
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader(title: 'Plantilla de esta actividad'),
            const SizedBox(height: 8),
            template.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => DepthCard(
                soft: true,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('No se pudo cargar la plantilla.'),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => ref.invalidate(
                        originalityTemplateProvider(widget.assignmentId),
                      ),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
              data: (t) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _ctrl,
                    enabled: canEdit && !_saving,
                    readOnly: !canEdit,
                    minLines: 8,
                    maxLines: 16,
                    maxLength: 20000,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: canEdit
                          ? 'Pega aquí el texto compartido (una línea por párrafo)…'
                          : 'Esta actividad no tiene plantilla.',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (t.updatedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Última modificación: '
                        '${DateFormat('d MMM yyyy, HH:mm', 'es').format(t.updatedAt!.toLocal())}',
                        style: context.textTheme.labelSmall
                            ?.copyWith(color: palette.textMuted),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (canEdit) ...[
                    FilledButton.icon(
                      onPressed: _dirty && !_saving ? () => _save() : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Guardar y reanalizar'),
                    ),
                    if (_saved.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _save(clear: true),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        icon:
                            const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Quitar plantilla'),
                      ),
                    ],
                  ] else
                    Text(
                      'Solo quien puede editar la actividad puede cambiar la plantilla.',
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: palette.textMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const OriginalityNoticeBox(),
          ],
        ),
      ),
    );
  }
}
