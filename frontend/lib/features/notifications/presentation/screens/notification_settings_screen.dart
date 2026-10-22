import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/backend_api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';

/// Preferencias de notificaciones por canal.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  final Map<String, bool> _channels = {
    'Mensajes': true,
    'Tareas': true,
    'Calificaciones': true,
    'Asistencia': true,
    'Anuncios': true,
    'Pagos': true,
  };
  bool _pushEnabled = true;
  /// `null` = todavía no se conoce el valor guardado (cargando o falló la
  /// carga): nunca se muestra "desactivado" por defecto.
  bool? _emailEnabled;
  bool _loadingEmail = true;
  bool _emailLoadFailed = false;
  bool _savingEmail = false;

  static const Map<String, IconData> _icons = {
    'Mensajes': Icons.chat_bubble_outline,
    'Tareas': Icons.assignment_rounded,
    'Calificaciones': Icons.grade_rounded,
    'Asistencia': Icons.how_to_reg_rounded,
    'Anuncios': Icons.campaign_rounded,
    'Pagos': Icons.payments_rounded,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreferences());
  }

  Future<void> _loadPreferences() async {
    final api = ref.read(backendApiClientProvider);
    if (api == null) {
      // Demo: sin servidor, la preferencia vive solo en la pantalla.
      setState(() {
        _emailEnabled = false;
        _loadingEmail = false;
      });
      return;
    }
    setState(() {
      _loadingEmail = true;
      _emailLoadFailed = false;
    });
    try {
      final data = await api.get('/notifications/preferences');
      if (!mounted) return;
      if (data is! Map || data['emailEnabled'] is! bool) {
        throw StateError('Respuesta inesperada');
      }
      setState(() {
        _emailEnabled = data['emailEnabled'] as bool;
        _loadingEmail = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingEmail = false;
        _emailLoadFailed = true;
      });
    }
  }

  Future<void> _setEmailEnabled(bool value) async {
    final previous = _emailEnabled;
    setState(() {
      _emailEnabled = value;
      _savingEmail = true;
    });
    final api = ref.read(backendApiClientProvider);
    if (api != null) {
      try {
        final data = await api.patch(
          '/notifications/preferences',
          data: {'emailEnabled': value},
        );
        if (mounted && data is Map && data['emailEnabled'] is bool) {
          setState(() => _emailEnabled = data['emailEnabled'] as bool);
        }
      } catch (error) {
        if (mounted) {
          setState(() => _emailEnabled = previous);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo guardar: $error')),
          );
        }
      }
    }
    if (mounted) setState(() => _savingEmail = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return StudentDetailScaffold(
      title: 'Notificaciones',
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Canales de entrega'),
          const SizedBox(height: 8),
          DepthCard(
            soft: true,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: _pushEnabled,
                  onChanged: (v) => setState(() => _pushEnabled = v),
                  secondary: const Icon(Icons.notifications_active_rounded),
                  title: const Text('Notificaciones push'),
                  subtitle: const Text('Avisos en este dispositivo'),
                ),
                SwitchListTile.adaptive(
                  value: _emailEnabled ?? false,
                  onChanged: _savingEmail || _emailEnabled == null
                      ? null
                      : _setEmailEnabled,
                  secondary: const Icon(Icons.mail_outline),
                  title: const Text('Correo electrónico'),
                  subtitle: Text(
                    _loadingEmail
                        ? 'Cargando…'
                        : _emailLoadFailed
                            ? 'No se pudo cargar tu preferencia'
                            : _savingEmail
                                ? 'Guardando…'
                                : 'Resumen por email',
                  ),
                ),
                if (_emailLoadFailed)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _loadPreferences,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Tipos de aviso'),
          const SizedBox(height: 8),
          DepthCard(
            soft: true,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: [
                for (final entry in _channels.entries)
                  SwitchListTile.adaptive(
                    value: entry.value && _pushEnabled,
                    onChanged: _pushEnabled
                        ? (v) => setState(() => _channels[entry.key] = v)
                        : null,
                    secondary: Icon(_icons[entry.key]),
                    title: Text(entry.key),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Puedes silenciar por completo un tipo de aviso o desactivar el push '
            'para no recibir nada en el dispositivo.',
            style:
                context.textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
