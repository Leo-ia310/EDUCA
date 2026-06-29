import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Encabezado verde lima con "EduCore" + acciones. Aparece en los 4
/// dashboards, igual a las referencias.
class DashboardTopBar extends StatelessWidget {
  const DashboardTopBar({
    super.key,
    this.onSettingsTap,
    this.onNotificationsTap,
    this.notificationsBadge = 0,
  });

  final VoidCallback? onSettingsTap;
  final VoidCallback? onNotificationsTap;
  final int notificationsBadge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: context.palette.limeDeep,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.school_rounded,
                color: Color(0xFF1E2218), size: 18),
          ),
          const SizedBox(width: 8),
          Text(
            'EduCore',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          if (onNotificationsTap != null)
            _TopIcon(
              icon: Icons.notifications_outlined,
              onTap: onNotificationsTap!,
              badge: notificationsBadge,
            ),
          if (onSettingsTap != null) ...[
            const SizedBox(width: 8),
            _TopIcon(icon: Icons.settings_outlined, onTap: onSettingsTap!),
          ],
        ],
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({required this.icon, required this.onTap, this.badge = 0});
  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: context.palette.cardElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
        ),
        if (badge > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: context.palette.danger,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                '$badge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class GreetingBanner extends StatelessWidget {
  const GreetingBanner({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: context.palette.lime,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.textTheme.headlineSmall?.copyWith(
              color: const Color(0xFF1E2218),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: context.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF34401C),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(height: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}
