import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';

/// Compañeros de clase en carrusel horizontal: círculos grandes con el nombre
/// debajo, para que se vean mejor. El resto (sin nombre) se resume en una
/// última ficha "+N".
class ClassmatesStrip extends StatelessWidget {
  const ClassmatesStrip({
    super.key,
    required this.names,
    required this.extraCount,
  });

  final List<String> names;
  final int extraCount;

  static const double _avatar = 60;

  @override
  Widget build(BuildContext context) {
    final hasExtra = extraCount > 0;
    final count = names.length + (hasExtra ? 1 : 0);
    return SizedBox(
      height: _avatar + 26,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          if (i >= names.length) return _ExtraTile(count: extraCount);
          return _ClassmateTile(name: names[i]);
        },
      ),
    );
  }
}

class _ClassmateTile extends StatelessWidget {
  const _ClassmateTile({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final firstName = name.trim().split(RegExp(r'\s+')).first;
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(name: name, size: ClassmatesStrip._avatar),
          const SizedBox(height: 6),
          Text(
            firstName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ExtraTile extends StatelessWidget {
  const _ExtraTile({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: ClassmatesStrip._avatar,
            height: ClassmatesStrip._avatar,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.limeSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              '+$count',
              style: context.textTheme.titleSmall?.copyWith(
                color: palette.limeDeep,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'más',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.textTheme.labelSmall
                ?.copyWith(color: palette.textMuted, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
