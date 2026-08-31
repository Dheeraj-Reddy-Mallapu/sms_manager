import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bubble position within a group — determines which corners get rounded.
enum BubblePosition { solo, first, middle, last }

class MessageBubble extends StatelessWidget {
  final SmsMessage message;
  final BubblePosition position;
  final bool isSelected;
  final String searchQuery;

  /// Called when user taps or long-presses to open context sheet.
  final void Function(SmsMessage)? onShowMenu;

  /// Called when tapping in multi-select mode.
  final void Function(SmsMessage)? onTap;

  const MessageBubble({
    super.key,
    required this.message,
    this.position = BubblePosition.solo,
    this.isSelected = false,
    this.searchQuery = '',
    this.onShowMenu,
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

    // Corner radii
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

    final double topPadding =
        (position == BubblePosition.first || position == BubblePosition.solo)
        ? 6
        : 1.5;

    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        if (onTap != null) {
          // Multi-select mode: toggle select
          onTap?.call(message);
        } else {
          onShowMenu?.call(message);
        }
      },
      onTap: () {
        if (onTap != null) {
          onTap?.call(message);
        } else {
          onShowMenu?.call(message);
        }
      },
      behavior: HitTestBehavior.translucent,
      child: Padding(
        padding: EdgeInsets.only(
          top: topPadding,
          bottom: 0,
          left: isOut ? 48 : 8,
          right: isOut ? 8 : 48,
        ),
        child: Row(
          mainAxisAlignment:
              isOut ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                    _buildBody(context, textColor),
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
      ),
    );
  }

  Widget _buildBody(BuildContext context, Color textColor) {
    final body = message.body;
    if (searchQuery.isNotEmpty) {
      return _buildSearchHighlight(body, textColor);
    }
    return _buildRichText(body, textColor, context);
  }

  Widget _buildSearchHighlight(String body, Color textColor) {
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

  /// Detects URLs, phone numbers, emails and makes them directly tappable
  /// using TapGestureRecognizer — no SelectableText needed.
  Widget _buildRichText(String body, Color textColor, BuildContext context) {
    final pattern = RegExp(
      r'(https?://[^\s]+)|(www\.[^\s]+)|(\+?[0-9][\d\s\-(]{7,}[0-9])|([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})',
    );
    final matches = pattern.allMatches(body);
    if (matches.isEmpty) {
      return Text(
        body,
        style: TextStyle(color: textColor, fontSize: 15),
      );
    }

    final spans = <InlineSpan>[];
    int lastEnd = 0;
    for (final m in matches) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: body.substring(lastEnd, m.start)));
      }
      final matched = m.group(0)!;
      spans.add(
        TextSpan(
          text: matched,
          style: TextStyle(
            color: textColor,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _launchUrl(matched),
        ),
      );
      lastEnd = m.end;
    }
    if (lastEnd < body.length) {
      spans.add(TextSpan(text: body.substring(lastEnd)));
    }

    return Text.rich(
      TextSpan(
        children: spans,
        style: TextStyle(color: textColor, fontSize: 15),
      ),
    );
  }

  void _launchUrl(String raw) async {
    Uri? uri;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      uri = Uri.tryParse(raw);
    } else if (raw.startsWith('www.')) {
      uri = Uri.tryParse('https://$raw');
    } else if (raw.contains('@')) {
      uri = Uri.tryParse('mailto:$raw');
    } else {
      // Phone number
      final digits = raw.replaceAll(RegExp(r'[\s\-()]'), '');
      uri = Uri.tryParse('tel:$digits');
    }
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
    return Icon(Icons.done_all, size: 12, color: color);
  }
}
