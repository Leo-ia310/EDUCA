import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

/// Acción rápida mostrada en la hoja inferior que abre el FAB de los
/// dashboards. Navega a [route] con `context.push` al tocarse.
class QuickActionEntry {
  const QuickActionEntry({
    required this.icon,
    required this.label,
    required this.route,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String route;
  final String? subtitle;
}

/// Muestra una hoja inferior con accesos rápidos según el rol. Cada opción
/// cierra la hoja y navega a su ruta.
Future<void> showQuickActionsSheet(
  BuildContext context, {
  required String title,
  required List<QuickActionEntry> actions,
}) {
  final palette = context.palette;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  title,
                  style: context.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              for (final a in actions)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: palette.limeSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(a.icon, color: palette.limeDeep, size: 20),
                  ),
                  title: Text(
                    a.label,
                    style: context.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  subtitle: a.subtitle != null ? Text(a.subtitle!) : null,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.push(a.route);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}
