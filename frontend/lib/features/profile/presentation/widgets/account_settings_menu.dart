import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../auth/presentation/auth_controller.dart';

/// Menú desplegable con las opciones de configuración de la cuenta
/// (apariencia, contraseña, notificaciones, ayuda y cerrar sesión).
///
/// Se reutiliza en el perfil del alumno y en el engranaje del dashboard.
/// [boxed] envuelve el ícono en la misma "caja" que los íconos de la barra
/// superior del dashboard, para que combine con el resto de acciones.
class AccountSettingsMenu extends ConsumerWidget {
  const AccountSettingsMenu({
    super.key,
    this.boxed = false,
    this.circular = false,
  });

  final bool boxed;

  /// Botón circular (para el header de bienvenida estilo fondo).
  final bool circular;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return PopupMenuButton<String>(
      tooltip: 'Opciones',
      padding: (boxed || circular) ? EdgeInsets.zero : const EdgeInsets.all(8),
      icon: (boxed || circular) ? null : const Icon(Icons.settings_outlined),
      child: circular
          ? Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.settings_outlined, color: Colors.white),
            )
          : boxed
              ? Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: palette.cardElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: const Icon(Icons.settings_outlined),
                )
              : null,
      onSelected: (v) async {
        switch (v) {
          case 'appearance':
            _showAppearanceSheet(context, ref);
          case 'password':
            context.push(Routes.changePassword);
          case 'notifications':
            context.push(Routes.notificationSettings);
          case 'help':
            context.push(Routes.help);
          case 'logout':
            await ref.read(authControllerProvider.notifier).signOut();
            if (context.mounted) context.go(Routes.login);
        }
      },
      itemBuilder: (_) => [
        _item('appearance', Icons.palette_outlined, 'Apariencia'),
        _item('password', Icons.lock_outline, 'Cambiar contraseña'),
        _item('notifications', Icons.notifications_none, 'Notificaciones'),
        _item('help', Icons.help_outline, 'Ayuda y soporte'),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: palette.danger),
            title: Text('Cerrar sesión',
                style: TextStyle(color: palette.danger),),
          ),
        ),
      ],
    );
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label) {
    return PopupMenuItem(
      value: value,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(label),
      ),
    );
  }
}

/// Lista de opciones de la cuenta como filas pastel con círculo de ícono
/// (mismo lenguaje visual del panel). Comparte acciones con [AccountSettingsMenu].
class AccountSettingsList extends ConsumerWidget {
  const AccountSettingsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _SettingsRow(
          icon: Icons.palette_outlined,
          label: 'Apariencia',
          color: const Color(0xFF8A5CF6),
          onTap: () => _showAppearanceSheet(context, ref),
        ),
        const SizedBox(height: 10),
        _SettingsRow(
          icon: Icons.lock_outline,
          label: 'Cambiar contraseña',
          color: const Color(0xFF4C8DF5),
          onTap: () => context.push(Routes.changePassword),
        ),
        const SizedBox(height: 10),
        _SettingsRow(
          icon: Icons.notifications_none,
          label: 'Notificaciones',
          color: const Color(0xFFF3993E),
          onTap: () => context.push(Routes.notificationSettings),
        ),
        const SizedBox(height: 10),
        _SettingsRow(
          icon: Icons.help_outline,
          label: 'Ayuda y soporte',
          color: const Color(0xFF33B7A0),
          onTap: () => context.push(Routes.help),
        ),
        const SizedBox(height: 10),
        _SettingsRow(
          icon: Icons.logout,
          label: 'Cerrar sesión',
          color: const Color(0xFFE5484D),
          onTap: () async {
            await ref.read(authControllerProvider.notifier).signOut();
            if (context.mounted) context.go(Routes.login);
          },
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = pastelSurface(color);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration:
                      BoxDecoration(color: s.vivid, shape: BoxShape.circle),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: context.textTheme.titleSmall?.copyWith(
                      color: s.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: s.inkMuted, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showAppearanceSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Consumer(
          builder: (context, ref, _) {
            final themeMode = ref.watch(themeControllerProvider);
            final palette = context.palette;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Text('Apariencia',
                          style: context.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),),
                    ],
                  ),
                ),
                RadioGroup<ThemeMode>(
                  groupValue: themeMode,
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(themeControllerProvider.notifier).set(v);
                      Navigator.pop(sheetContext);
                    }
                  },
                  child: Column(
                    children: [
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.system,
                        title: const Text('Seguir sistema'),
                        activeColor: palette.limeDeep,
                      ),
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.light,
                        title: const Text('Tema claro'),
                        activeColor: palette.limeDeep,
                      ),
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.dark,
                        title: const Text('Tema oscuro'),
                        activeColor: palette.limeDeep,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      );
    },
  );
}
