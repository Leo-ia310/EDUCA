import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities.dart';

class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.onSend,
    required this.onPickAttachment,
    this.pendingAttachment,
    this.onRemoveAttachment,
    this.sending = false,
  });

  final Future<void> Function(String text) onSend;
  final Future<void> Function() onPickAttachment;
  final MessageAttachment? pendingAttachment;
  final VoidCallback? onRemoveAttachment;
  final bool sending;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final v = _controller.text.trim().isNotEmpty ||
          widget.pendingAttachment != null;
      if (v != _canSend) setState(() => _canSend = v);
    });
  }

  @override
  void didUpdateWidget(covariant ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final v = _controller.text.trim().isNotEmpty ||
        widget.pendingAttachment != null;
    if (v != _canSend) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _canSend = v);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (widget.sending) return;
    final text = _controller.text.trim();
    if (text.isEmpty && widget.pendingAttachment == null) return;
    await widget.onSend(text);
    _controller.clear();
    _focus.requestFocus();
    setState(() => _canSend = widget.pendingAttachment != null);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.pendingAttachment != null)
              _PendingAttachment(
                attachment: widget.pendingAttachment!,
                onRemove: widget.onRemoveAttachment,
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file_rounded),
                  color: palette.limeDeep,
                  onPressed: widget.sending ? null : widget.onPickAttachment,
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Escribe un mensaje…',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _canSend && !widget.sending
                        ? palette.limeDeep
                        : palette.surfaceAlt,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: widget.sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.send_rounded,
                            color: _canSend
                                ? const Color(0xFF1E2218)
                                : palette.textMuted,
                          ),
                    onPressed: (_canSend && !widget.sending) ? _send : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingAttachment extends StatelessWidget {
  const _PendingAttachment({required this.attachment, this.onRemove});
  final MessageAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: palette.limeSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              attachment.isImage
                  ? Icons.image_outlined
                  : Icons.description_outlined,
              size: 18,
              color: palette.limeDeep,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (onRemove != null)
              InkWell(
                onTap: onRemove,
                child: Icon(Icons.close_rounded,
                    size: 18, color: palette.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}
