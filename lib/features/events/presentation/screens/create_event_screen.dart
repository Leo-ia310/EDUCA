import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/validators.dart';
import '../../data/events_store.dart';

/// Formulario para crear un evento/anuncio institucional. Al guardar lo
/// agrega al [eventsStoreProvider] y vuelve, quedando visible en Anuncios.
class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  String _audience = 'Toda la institución';
  bool _loading = false;

  static const _audiences = <String>[
    'Toda la institución',
    'Padres y tutores',
    'Estudiantes',
    'Docentes',
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    ref.read(eventsStoreProvider.notifier).add(
          SchoolEvent(
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            date: _date,
            audience: _audience,
          ),
        );
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Evento publicado correctamente.')),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear evento'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _titleCtrl,
                    validator: (v) =>
                        Validators.required(v, label: 'El título'),
                    decoration: const InputDecoration(
                      labelText: 'Título del evento',
                      prefixIcon: Icon(Icons.title_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descCtrl,
                    minLines: 3,
                    maxLines: 5,
                    validator: (v) =>
                        Validators.required(v, label: 'La descripción'),
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(16),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha',
                        prefixIcon: Icon(Icons.calendar_month_outlined),
                      ),
                      child: Text(
                        DateFormat("EEEE d 'de' MMMM y", 'es').format(_date),
                        style: context.textTheme.bodyLarge,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _audience,
                    decoration: const InputDecoration(
                      labelText: 'Dirigido a',
                      prefixIcon: Icon(Icons.groups_2_outlined),
                    ),
                    items: [
                      for (final a in _audiences)
                        DropdownMenuItem(value: a, child: Text(a)),
                    ],
                    onChanged: (v) => setState(() => _audience = v ?? _audience),
                  ),
                  const SizedBox(height: 26),
                  FilledButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: const Text('Publicar evento'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'El evento aparecerá en Anuncios y en el panel de los '
                    'destinatarios seleccionados.',
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
