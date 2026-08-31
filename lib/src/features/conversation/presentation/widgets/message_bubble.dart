import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';

/// Bubble position within a group — determines which corners get rounded.
enum BubblePosition { solo, first, middle, last }

class MessageBubble extends StatelessWidget {
  final SmsMessage message;
  final BubblePosition position;
  final bool isSelected;
  final String searchQuery;

  /// Called when user long-presses the bubble.
  final void Function(SmsMessage)? onLongPress;

  /// Called when user swipes right (reply gesture).
  final void Function(SmsMessage)? onReply;

  /// Called when tapping for multi-select.
  final void Function(SmsMessage)? onTap;

  const MessageBubble({
    super.key,
    required this.message,
    this.position = BubblePosition.solo,
    this.isSelected = false,
    this.searchQuery = '',
    this.onLongPress,
    this.onReply,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOut = message.isOutgoing;

    // Bubble colour
    final bubbleColor = isSelected
        ? colorScheme.primary.withAlpha(50)
        : isOut
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final textColor = isOut ? colorScheme.onPrimary : colorScheme.onSurface;
    final timeColor = isOut
        ? colorScheme.onPrimary.withAlpha(179)
        : colorScheme.onSurfaceVariant;

    // Corner radii — give a "tail" only to the outermost bubble of a group
    const r = Radius.circular(18);
    const rSmall = Radius.circular(4);
    BorderRadius borderRadius;
    if (isOut) {
      borderRadius = BorderRadius.only(
        topLeft: r,
        bottomLeft: r,
        topRight:
            (position == BubblePosition.solo ||
                position == BubblePosition.first)
            ? r
            : rSmall,
        bottomRight:
            (position == BubblePosition.solo || position == BubblePosition.last)
            ? rSmall
            : r,
      );
    } else {
      borderRadius = BorderRadius.only(
        topRight: r,
        bottomRight: r,
        topLeft:
            (position == BubblePosition.solo ||
                position == BubblePosition.first)
            ? r
            : rSmall,
        bottomLeft:
            (position == BubblePosition.solo || position == BubblePosition.last)
            ? rSmall
            : r,
      );
    }

    final timeStr = DateFormat.jm().format(
      DateTime.fromMillisecondsSinceEpoch(message.date),
    );

    final bool showTime =
        position == BubblePosition.solo || position == BubblePosition.last;

    // Vertical spacing
    final double topPadding =
        (position == BubblePosition.first || position == BubblePosition.solo)
        ? 6
        : 1.5;

    Widget content = Padding(
      padding: EdgeInsets.only(
        top: topPadding,
        bottom: 0,
        left: isOut ? 48 : 8,
        right: isOut ? 8 : 48,
      ),
      child: Row(
          mainAxisAlignment: isOut
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: borderRadius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: isOut
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // Message body with search highlight
                    _buildBody(context, textColor),

                    // Status row: time + delivery icon + star
                    if (showTime)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (message.isStarred) ...[
                              Icon(
                                Icons.star_rounded,
                                size: 10,
                                color: timeColor,
                              ),
                              const SizedBox(width: 3),
                            ],
                            Text(
                              timeStr,
                              style: TextStyle(fontSize: 10, color: timeColor),
                            ),
                            if (isOut) ...[
                              const SizedBox(width: 4),
                              _statusIcon(timeColor),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

    content = GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        onLongPress?.call(message);
      },
      onTap: () => onTap?.call(message),
      behavior: HitTestBehavior.translucent,
      child: content,
    );

    if (isOut) return content;

    return Dismissible(
      key: ValueKey('msg_${message.id}'),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Icon(Icons.reply_rounded, color: colorScheme.onSurfaceVariant),
      ),
      confirmDismiss: (direction) async {
        HapticFeedback.lightImpact();
        onReply?.call(message);
        return false; // Don't actually dismiss the widget
      },
      child: content,
    );
  }

  Widget _buildBody(BuildContext context, Color textColor) {
    final body = message.body;
    if (searchQuery.isEmpty) {
      return _buildRichText(body, textColor, context);
    }

    // Highlight search matches
    final lower = body.toLowerCase();
    final queryLower = searchQuery.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final idx = lower.indexOf(queryLower, start);
      if (idx == -1) {
        spans.add(TextSpan(text: body.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: body.substring(start, idx)));
      }
      spans.add(
        TextSpan(
          text: body.substring(idx, idx + searchQuery.length),
          style: const TextStyle(
            backgroundColor: Color(0xFFFFEB3B),
            color: Colors.black,
          ),
        ),
      );
      start = idx + searchQuery.length;
    }
    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(color: textColor, fontSize: 15),
    );
  }

  /// Detects URLs, phone numbers, emails and makes them tappable.
  Widget _buildRichText(String body, Color textColor, BuildContext context) {
    // Simple regex for common patterns
    final pattern = RegExp(
      r'(https?://[^\s]+)|(www\.[^\s]+)|(\+?[0-9][\d\s\-()]{7,}[0-9])|([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})',
    );
    final matches = pattern.allMatches(body);
    if (matches.isEmpty) {
      return SelectableText(
        body,
        style: TextStyle(color: textColor, fontSize: 15),
        onTap: () => onTap?.call(message),
      );
    }

    final spans = <InlineSpan>[];
    int lastEnd = 0;
    for (final m in matches) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: body.substring(lastEnd, m.start)));
      }
      spans.add(
        TextSpan(
          text: m.group(0),
          style: TextStyle(
            color: textColor,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      lastEnd = m.end;
    }
    if (lastEnd < body.length) {
      spans.add(TextSpan(text: body.substring(lastEnd)));
    }

    return SelectableText.rich(
      TextSpan(
        children: spans,
        style: TextStyle(color: textColor, fontSize: 15),
      ),
      onTap: () => onTap?.call(message),
    );
  }

  Widget _statusIcon(Color color) {
    if (message.isOptimistic) {
      return SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
      );
    }
    if (message.isFailed) {
      return Icon(Icons.error_outline, size: 12, color: Colors.red.shade300);
    }
    // Delivered (double check)
    return Icon(Icons.done_all, size: 12, color: color);
  }
}
