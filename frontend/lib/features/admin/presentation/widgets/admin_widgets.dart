import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../../shared/models/app_role.dart';

/// Color de cada rol (tarjetas y etiquetas).
Color roleColor(AppRole r) => switch (r) {
      AppRole.teacher => const Color(0xFF4C8DF5),
      AppRole.student => const Color(0xFFF3993E),
      AppRole.parent => const Color(0xFF9A6BE0),
      AppRole.coordinator => const Color(0xFF33B7A0),
      AppRole.admin => const Color(0xFFE5484D),
      AppRole.director => const Color(0xFF2FA869),
    };

IconData roleIcon(AppRole r) => switch (r) {
      AppRole.teacher => Icons.badge_rounded,
      AppRole.student => Icons.backpack_rounded,
      AppRole.parent => Icons.family_restroom_rounded,
      AppRole.coordinator => Icons.manage_accounts_rounded,
      AppRole.admin => Icons.admin_panel_settings_rounded,
      AppRole.director => Icons.workspace_premium_rounded,
    };

/// Hoja inferior con el estilo del panel (borde grueso arriba), con título y
/// contenido desplazable que respeta el teclado.
Future<T?> showBrutalSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final ink = Brutal.ink(ctx);
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: ink, width: Brutal.border),
            left: BorderSide(color: ink, width: Brutal.border),
            right: BorderSide(color: ink, width: Brutal.border),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        // Material propio: los ListTile/Switch necesitan un ancestro Material
        // sin color de fondo intermedio.
        child: Material(
          type: MaterialType.transparency,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: ctx.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                child,
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<bool> confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirmar eliminación'),
      content: Text('¿Eliminar $what? Esta acción no se puede deshacer.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Campo de texto con borde grueso.
class BrutalTextField extends StatelessWidget {
  const BrutalTextField({
    super.key,
    required this.controller,
    required this.label,
    this.keyboardType,
    this.icon,
    this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final IconData? icon;
  final ValueChanged<String>? onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c, width: Brutal.border),
        );
    final ink = Brutal.ink(context);
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        prefixIcon: icon == null ? null : Icon(icon),
        isDense: true,
        border: border(ink),
        enabledBorder: border(ink),
        focusedBorder: border(context.palette.accentDeep),
        errorBorder: border(context.palette.danger),
        focusedErrorBorder: border(context.palette.danger),
      ),
    );
  }
}

/// Título de campo dentro de un formulario.
class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          text,
          style: context.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: context.palette.textMuted,
          ),
        ),
      );
}

/// Fila de lista del panel admin: cuadro con inicial/ícono, título, subtítulo
/// y una etiqueta opcional.
class AdminTile extends StatelessWidget {
  const AdminTile({
    super.key,
    required this.title,
    required this.color,
    this.subtitle,
    this.caption,
    this.leadingText,
    this.leadingIcon,
    this.onTap,
    this.dimmed = false,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? caption;
  final Color color;
  final String? leadingText;
  final IconData? leadingIcon;
  final VoidCallback? onTap;
  final bool dimmed;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = context.pastel(color);
    final ink = Brutal.ink(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: BrutalBox(
          onTap: onTap,
          color: s.surface,
          radius: Radii.md,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.vivid,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: ink, width: Brutal.border),
                ),
                child: leadingIcon != null
                    ? Icon(leadingIcon, color: Colors.white, size: 24)
                    : Text(
                        leadingText ?? '?',
                        style: context.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall?.copyWith(
                        color: s.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: s.inkMuted),
                      ),
                    if (caption != null && caption!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(Radii.pill),
                          border: Border.all(color: ink, width: 1.5),
                        ),
                        child: Text(
                          caption!,
                          style: context.textTheme.labelSmall?.copyWith(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: ink, width: Brutal.border),
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      color: Colors.black,
                      size: 18,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra de búsqueda con borde grueso.
class AdminSearchField extends StatelessWidget {
  const AdminSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
  });

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final ink = Brutal.ink(context);
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c, width: Brutal.border),
        );
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded),
        isDense: true,
        border: border(ink),
        enabledBorder: border(ink),
        focusedBorder: border(context.palette.accentDeep),
      ),
    );
  }
}

/// Color de pastel de una materia (reexport para las pantallas).
Color subjectTone(String subject) => subjectColor(subject);
