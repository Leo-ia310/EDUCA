import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/section_header.dart';

/// Preferencias de notificaciones por canal. En modo demo el estado vive en la
/// pantalla; con backend real persistiría en `institution_settings`/perfil.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final Map<String, bool> _channels = {
    'Mensajes': true,
    'Tareas': true,
    'Calificaciones': true,
    'Asistencia': true,
    'Anuncios': true,
    'Pagos': true,
  };
  bool _pushEnabled = true;
  bool _emailEnabled = false;

  static const Map<String, IconData> _icons = {
    'Mensajes': Icons.chat_bubble_outline,
    'Tareas': Icons.assignment_outlined,
    'Calificaciones': Icons.grade_outlined,
    'Asistencia': Icons.how_to_reg_outlined,
    'Anuncios': Icons.campaign_outlined,
    'Pagos': Icons.payments_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const SectionHeader(title: 'Canales de entrega'),
          const SizedBox(height: 8),
          EduCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: _pushEnabled,
                  onChanged: (v) => setState(() => _pushEnabled = v),
                  activeThumbColor: palette.limeDeep,
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Notificaciones push'),
                  subtitle: const Text('Avisos en este dispositivo'),
                ),
                SwitchListTile.adaptive(
                  value: _emailEnabled,
                  onChanged: (v) => setState(() => _emailEnabled = v),
                  activeThumbColor: palette.limeDeep,
                  secondary: const Icon(Icons.mail_outline),
                  title: const Text('Correo electrónico'),
                  subtitle: const Text('Resumen por email'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Tipos de aviso'),
          const SizedBox(height: 8),
          EduCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: [
                for (final entry in _channels.entries)
                  SwitchListTile.adaptive(
                    value: entry.value && _pushEnabled,
                    onChanged: _pushEnabled
                        ? (v) => setState(() => _channels[entry.key] = v)
                        : null,
                    activeThumbColor: palette.limeDeep,
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
            style: context.textTheme.bodySmall
                ?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
