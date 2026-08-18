import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';

class ClassmatesStrip extends StatelessWidget {
  const ClassmatesStrip({
    super.key,
    required this.names,
    required this.extraCount,
  });

  final List<String> names;
  final int extraCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shown = names.take(4).toList();
    return SizedBox(
      height: 44,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 28.0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: UserAvatar(name: shown[i], size: 36),
              ),
            ),
          if (extraCount > 0)
            Positioned(
              left: shown.length * 28.0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.limeDeep,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '+$extraCount',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E2218),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
