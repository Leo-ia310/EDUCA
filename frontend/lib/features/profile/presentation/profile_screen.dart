import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/edu_card.dart';
import '../../../core/widgets/educa_bottom_nav.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final institution = ref.watch(authControllerProvider).institution;
    final themeMode = ref.watch(themeControllerProvider);
    final palette = context.palette;

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
          const SizedBox(height: 24),
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
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
          const SizedBox(height: 32),

          const SectionHeader(title: 'Apariencia'),
          const SizedBox(height: 8),
          EduCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: RadioGroup<ThemeMode>(
              groupValue: themeMode,
              onChanged: (v) {
                if (v != null) {
                  ref.read(themeControllerProvider.notifier).set(v);
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
          ),
          const SizedBox(height: 24),

          const SectionHeader(title: 'Cuenta'),
          const SizedBox(height: 8),
          EduCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _ProfileAction(
                  icon: Icons.lock_outline,
                  label: 'Cambiar contraseña',
                  onTap: () => context.push(Routes.changePassword),
                ),
                Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
                _ProfileAction(
                  icon: Icons.notifications_none,
                  label: 'Notificaciones',
                  onTap: () => context.push(Routes.notificationSettings),
                ),
                Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
                _ProfileAction(
                  icon: Icons.help_outline,
                  label: 'Ayuda y soporte',
                  onTap: () => context.push(Routes.help),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) context.go(Routes.institutionCode);
            },
            icon: Icon(Icons.logout, color: palette.danger),
            label: Text('Cerrar sesión',
                style: TextStyle(color: palette.danger)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: palette.danger.withValues(alpha: 0.4)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: context.palette.textMuted),
      title: Text(label,
          style: context.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
