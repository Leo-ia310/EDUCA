import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../theme/app_theme.dart';

/// Bottom nav con 4 ítems estándar (Inicio, Horario, Alertas, Perfil).
class EducaBottomNav extends StatelessWidget {
  const EducaBottomNav({
    super.key,
    required this.current,
    required this.onTap,
  });

  final EducaNavItem current;
  final ValueChanged<EducaNavItem> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final item in EducaNavItem.values)
                _NavButton(
                  item: item,
                  active: item == current,
                  onTap: () => onTap(item),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum EducaNavItem {
  home(Icons.home_rounded, AppStrings.navHome),
  schedule(Icons.calendar_today_rounded, AppStrings.navSchedule),
  alerts(Icons.notifications_rounded, AppStrings.navAlerts),
  profile(Icons.person_rounded, AppStrings.navProfile);

  const EducaNavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final EducaNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final activeColor = palette.limeDeep;
    final inactiveColor = palette.textMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        // FittedBox + mainAxisSize.min: el ítem se reduce si por un frame de
        // transición recibe una altura diminuta, en vez de desbordar.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                color: active ? activeColor : inactiveColor,
                size: 24,
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: context.textTheme.labelSmall?.copyWith(
                  color: active ? activeColor : inactiveColor,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 3,
                width: active ? 20 : 0,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
