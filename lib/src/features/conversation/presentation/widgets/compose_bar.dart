import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';

import 'scroll_to_bottom_fab.dart';

class ComposeBar extends StatefulWidget {
  final String address;
  final bool isSending;
  final SmsMessage? replyToMessage;
  final void Function(String body) onSend;
  final VoidCallback? onDismissReply;

  const ComposeBar({
    super.key,
    required this.address,
    required this.onSend,
    this.isSending = false,
    this.replyToMessage,
    this.onDismissReply,
  });

  @override
  State<ComposeBar> createState() => _ComposeBarState();
}

class _ComposeBarState extends State<ComposeBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _charCount = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _charCount = _controller.text.length);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isSending) return;
    HapticFeedback.lightImpact();
    widget.onSend(text);
    _controller.clear();
    setState(() => _charCount = 0);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEmpty = _charCount == 0;

    // SMS character count info
    const smsLimit = 160;
    final parts = (_charCount / smsLimit).ceil().clamp(1, 99);
    final remaining = parts * smsLimit - _charCount;
    final showCharCount = _charCount > 100;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reply context banner
        if (widget.replyToMessage != null)
          ReplyBanner(
            message: widget.replyToMessage!,
            onDismiss: () => widget.onDismissReply?.call(),
          ),

        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Text field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          maxLines: 5,
                          minLines: 1,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.newline,
                          keyboardType: TextInputType.multiline,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Message',
                            hintStyle: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 15,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                        ),
                        if (showCharCount)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: 12,
                              bottom: 4,
                            ),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '$remaining/$parts',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: remaining < 20
                                      ? colorScheme.error
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Send button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: isEmpty
                        ? colorScheme.surfaceContainerHighest
                        : colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: widget.isSending
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : IconButton(
                          onPressed: isEmpty ? null : _send,
                          icon: Icon(
                            Icons.send_rounded,
                            color: isEmpty
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.onPrimary,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
