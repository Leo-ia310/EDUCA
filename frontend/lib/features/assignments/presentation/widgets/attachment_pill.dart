import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities.dart';

class AttachmentPill extends StatelessWidget {
  const AttachmentPill({
    super.key,
    required this.attachment,
    this.onTap,
    this.onRemove,
  });

  final AssignmentAttachment attachment;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  IconData get _icon {
    if (attachment.isImage) return Icons.image_rounded;
    if (attachment.extension == 'PDF') return Icons.picture_as_pdf_rounded;
    if (attachment.extension == 'DOCX') return Icons.description_rounded;
    return Icons.insert_drive_file_rounded;
  }

  String get _size {
    final b = attachment.sizeBytes;
    if (b == null) return '';
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceAlt,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 18, color: palette.accentDeep),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (_size.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  _size,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
              if (onRemove != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Quitar',
                  child: InkWell(
                    onTap: onRemove,
                    child: Icon(Icons.close_rounded,
                        size: 16, color: palette.textMuted,),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
