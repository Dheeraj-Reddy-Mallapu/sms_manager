import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

class ComposeBar extends StatefulWidget {
  final String address;
  final bool isSending;
  final void Function(String body) onSend;

  const ComposeBar({
    super.key,
    required this.address,
    required this.onSend,
    this.isSending = false,
  });

  @override
  State<ComposeBar> createState() => _ComposeBarState();
}

class _ComposeBarState extends State<ComposeBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _charCount = 0;

  static const _smsLimit = 160;
  static const _multipartLimit = 153; // GSM-7 chars per part when multipart

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

  /// Returns (remaining chars in current part, total parts)
  (int, int) get _smsInfo {
    if (_charCount == 0) return (_smsLimit, 1);
    if (_charCount <= _smsLimit) {
      return (_smsLimit - _charCount, 1);
    }
    final parts = ((_charCount - 1) ~/ _multipartLimit) + 1;
    final usedInCurrentPart = _charCount - (_multipartLimit * (parts - 1));
    final remaining = _multipartLimit - usedInCurrentPart;
    return (remaining, parts);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEmpty = _charCount == 0;
    final (remaining, parts) = _smsInfo;
    final isNearLimit = remaining <= 20;
    final isMultipart = parts > 1;

    return Container(
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
            // Text field + char counter
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
                    // SMS character counter — always shown when typing
                    if (!isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                          right: 14,
                          bottom: 6,
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            isMultipart
                                ? '$remaining / $parts SMS'
                                : '$remaining',
                            style: TextStyle(
                              fontSize: 10,
                              color: isNearLimit
                                  ? colorScheme.error
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: isNearLimit
                                  ? FontWeight.w600
                                  : FontWeight.normal,
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
    );
  }
}
