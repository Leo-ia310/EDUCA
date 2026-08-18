import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/section_header.dart';

/// Centro de ayuda: preguntas frecuentes + contacto de soporte.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faqs = <(String, String)>[
    (
      '¿Cómo cambio mi contraseña?',
      'Ve a Perfil → Cuenta → Cambiar contraseña, ingresa tu contraseña actual '
          'y la nueva dos veces.',
    ),
    (
      '¿Cómo veo el boletín de mi hijo/a?',
      'Desde el panel de Padre pulsa "Boletín", o entra a Notas y usa el botón '
          'de descargar. Podrás verlo en PDF y compartirlo.',
    ),
    (
      '¿Cómo tomo asistencia sin internet?',
      'La asistencia funciona offline: se guarda en el dispositivo y se '
          'sincroniza automáticamente cuando vuelve la conexión.',
    ),
    (
      '¿Cómo contacto a un docente?',
      'Usa la sección de Chat, o el botón de mensaje junto a cada materia en '
          'el panel de Padre.',
    ),
    (
      '¿Cómo pago una cuota?',
      'En Pagos selecciona el cargo pendiente, pulsa "Pagar ahora" y elige el '
          'método de pago. Recibirás un recibo al finalizar.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Ayuda y soporte'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const SectionHeader(title: 'Preguntas frecuentes'),
          const SizedBox(height: 8),
          EduCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Column(
              children: [
                for (final faq in _faqs)
                  Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding:
                          const EdgeInsets.symmetric(horizontal: 10),
                      childrenPadding:
                          const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      iconColor: palette.limeDeep,
                      collapsedIconColor: palette.textMuted,
                      title: Text(
                        faq.$1,
                        style: context.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(faq.$2,
                              style: context.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Contacto'),
          const SizedBox(height: 8),
          EduCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _ContactTile(
                  icon: Icons.mail_outline,
                  label: 'Correo de soporte',
                  value: 'soporte@educa360.app',
                  onTap: () => _copied(context, 'soporte@educa360.app'),
                ),
                Divider(
                  height: 1,
                  color:
                      Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
                _ContactTile(
                  icon: Icons.phone_outlined,
                  label: 'Teléfono',
                  value: '+505 8888 0000',
                  onTap: () => _copied(context, '+505 8888 0000'),
                ),
                Divider(
                  height: 1,
                  color:
                      Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
                _ContactTile(
                  icon: Icons.schedule_outlined,
                  label: 'Horario de atención',
                  value: 'Lun a Vie · 8:00 – 17:00',
                  onTap: null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Educa360 · versión 0.1.0',
              style: context.textTheme.labelSmall
                  ?.copyWith(color: palette.textMuted),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _copied(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copiado: $value')),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: context.palette.textMuted),
      title: Text(label,
          style: context.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
      subtitle: Text(value),
      trailing:
          onTap != null ? const Icon(Icons.copy_rounded, size: 18) : null,
      onTap: onTap,
    );
  }
}
