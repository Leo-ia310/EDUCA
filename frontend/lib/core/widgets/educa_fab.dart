import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'brutal.dart';

class EducaFab extends StatelessWidget {
  const EducaFab({
    super.key,
    required this.onPressed,
    this.icon = Icons.add_rounded,
  });

  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (Brutal.active(context)) {
      return BrutalBox(
        onTap: onPressed,
        color: context.palette.accentDeep,
        radius: Radii.md,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, size: 28, color: Colors.white),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: context.palette.accentDeep.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: onPressed,
        child: Icon(icon, size: 28),
      ),
    );
  }
}
