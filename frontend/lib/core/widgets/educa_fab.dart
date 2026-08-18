import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: context.palette.limeDeep.withValues(alpha: 0.35),
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
