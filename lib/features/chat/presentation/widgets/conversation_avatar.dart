import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/entities.dart';

class ConversationAvatar extends StatelessWidget {
  const ConversationAvatar({
    super.key,
    required this.conversation,
    this.size = 48,
  });

  final Conversation conversation;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (conversation.kind == ConversationKind.group) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: palette.limeSoft,
          borderRadius: BorderRadius.circular(size / 3),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.groups_rounded,
            color: palette.limeDeep, size: size * 0.55),
      );
    }
    final other = conversation.counterpart;
    final avatar = UserAvatar(
      name: other?.name ?? conversation.title,
      imageUrl: other?.avatarUrl,
      size: size,
    );
    if (other?.isOnline == true) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: palette.success,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return avatar;
  }
}
