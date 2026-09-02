import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/edu_card.dart';
import '../../../core/widgets/educa_bottom_nav.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../dashboard/data/dashboard_data.dart';
import '../../dashboard/presentation/widgets/grades_block.dart';
import '../../dashboard/providers.dart';
import '../../notifications/domain/entities.dart';
import '../../notifications/providers.dart';

/// Perfil del alumno: identidad (avatar + nombre) + sus tarjetas de
/// notificaciones y notas. Las opciones de configuración viven en un menú
/// desplegable en la esquina.
class StudentProfileScreen extends ConsumerWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final institution = ref.watch(authControllerProvider).institution;
    final palette = context.palette;

    final notifications =
        ref.watch(notificationsFeedProvider).valueOrNull ?? const [];
    final topNotifications = notifications.take(4).toList();
    final data = ref.watch(studentDashboardProvider).valueOrNull ??
        StudentDashboardData.mock();

    return AppScaffold(
      bottomNav: EducaBottomNav(
        current: EducaNavItem.profile,
        onTap: (i) {
          if (i == EducaNavItem.home && user != null) {
            context.go(user.activeRole.dashboardRoute);
          }
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Menú de opciones en la esquina.
          Align(
            alignment: Alignment.topRight,
            child: _SettingsMenu(),
          ),

          // Identidad
          Center(
            child: Column(
              children: [
                UserAvatar(
                  name: user?.fullName ?? 'Usuario',
                  imageUrl: user?.avatarUrl,
                  size: 96,
                  ringColor: palette.limeDeep,
                ),
                const SizedBox(height: 12),
                Text(
                  user?.fullName ?? 'Invitado',
                  style: context.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (user != null)
                  Text(
                    user.activeRole.label,
                    style: context.textTheme.bodyMedium
                        ?.copyWith(color: palette.textMuted),
                  ),
                if (institution != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4,),
                    decoration: BoxDecoration(
                      color: palette.limeSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      institution.name,
                      style: context.textTheme.labelMedium?.copyWith(
                        color: palette.limeDeep,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Notificaciones
          Row(
            children: [
              const Expanded(child: SectionHeader(title: 'Notificaciones')),
              if (notifications.isNotEmpty)
                GestureDetector(
                  onTap: () => context.push(Routes.alerts),
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    'Ver todas',
                    style: context.textTheme.labelMedium?.copyWith(
                      color: palette.limeDeep,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (topNotifications.isEmpty)
            const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'Sin notificaciones',
              subtitle: 'Aquí verás tus avisos, tareas y notas.',
            )
          else
            for (final n in topNotifications)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _NotificationCard(notification: n),
              ),
          const SizedBox(height: 24),

          // Notas
          const SectionHeader(title: 'Mis Notas'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => context.push(Routes.grades),
            child: GradesBlock(
              grades: data.grades,
              average: data.averageScore,
              onDownload: () => context.push(Routes.reports),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification});
  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = _channelColor(notification.channel, palette);
    return EduCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: notification.deepLink == null
          ? null
          : () => context.push(notification.deepLink!),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(notification.iconOverride ?? notification.channel.icon,
                color: accent, size: 20,),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  notification.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _relative(notification.receivedAt),
                style: context.textTheme.labelSmall
                    ?.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: 6),
              if (!notification.read)
                Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Menú desplegable con las opciones de configuración de la cuenta.
class _SettingsMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      tooltip: 'Opciones',
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
            if (context.mounted) context.go(Routes.institutionCode);
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

Color _channelColor(NotificationChannel channel, AppPalette palette) {
  return switch (channel) {
    NotificationChannel.message => palette.info,
    NotificationChannel.task => palette.warning,
    NotificationChannel.grade => palette.success,
    NotificationChannel.attendance => palette.info,
    NotificationChannel.announcement => palette.limeDeep,
    NotificationChannel.payment => palette.warning,
    NotificationChannel.system => palette.textMuted,
  };
}

String _relative(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays < 7) return 'hace ${diff.inDays} d';
  return DateFormat('d MMM', 'es').format(d);
}
