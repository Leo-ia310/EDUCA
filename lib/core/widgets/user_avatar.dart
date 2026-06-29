import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 40,
    this.ringColor,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final Color? ringColor;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final core = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.limeSoft,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: imageUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _initialsLabel(context),
              ),
            )
          : _initialsLabel(context),
    );

    if (ringColor == null) return core;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor!, width: 2),
      ),
      child: core,
    );
  }

  Widget _initialsLabel(BuildContext context) => Text(
        _initials,
        style: context.textTheme.titleSmall?.copyWith(
          color: context.palette.limeDeep,
          fontWeight: FontWeight.w800,
        ),
      );
}
