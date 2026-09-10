import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
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
