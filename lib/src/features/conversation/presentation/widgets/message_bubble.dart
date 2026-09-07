import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';
import 'package:sms_manager/src/core/utils/smart_text_parser.dart';
import 'package:sms_manager/src/features/conversation/presentation/widgets/entity_bottom_sheet.dart';

/// Bubble position within a group — determines which corners get rounded.
enum BubblePosition { solo, first, middle, last }

class MessageBubble extends StatelessWidget {
  final SmsMessage message;
  final BubblePosition position;
  final bool isSelected;
  final bool isHighlighted;
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
    this.isHighlighted = false,
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
        : isHighlighted
        ? colorScheme.tertiaryContainer
        : isOut
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final textColor = isHighlighted
        ? colorScheme.onTertiaryContainer
        : isOut ? colorScheme.onPrimary : colorScheme.onSurface;
    final timeColor = isHighlighted
        ? colorScheme.onTertiaryContainer.withAlpha(179)
        : isOut
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

    final tokens = SmartTextParser.parse(body);
    final otps = tokens.where((t) => t.type == TokenType.otp).toList();

    Widget content = _buildSmartText(tokens, textColor, context);

    if (otps.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: otps.map((otp) {
              return ActionChip(
                label: Text('Copy ${otp.text}'),
                avatar: const Icon(Icons.copy, size: 16),
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: otp.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Code copied'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              );
            }).toList(),
          ),
        ],
      );
    }

    return content;
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

  Widget _buildSmartText(
    List<MessageToken> tokens,
    Color textColor,
    BuildContext context,
  ) {
    if (tokens.isEmpty) return const SizedBox.shrink();

    final spans = <InlineSpan>[];
    for (final token in tokens) {
      if (token.type == TokenType.text) {
        spans.add(TextSpan(text: token.text));
      } else {
        IconData? iconData;
        switch (token.type) {
          case TokenType.url:
            iconData = Icons.language;
            break;
          case TokenType.phone:
            iconData = Icons.phone;
            break;
          case TokenType.email:
            iconData = Icons.mail;
            break;
          case TokenType.date:
            iconData = Icons.calendar_today;
            break;
          case TokenType.otp:
            iconData = Icons.password;
            break;
          default:
            break;
        }

        if (iconData != null) {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 2, left: 2),
                child: Icon(
                  iconData,
                  size: 14,
                  color: textColor.withValues(alpha: 0.8),
                ),
              ),
            ),
          );
        }

        spans.add(
          TextSpan(
            text: token.text,
            style: TextStyle(
              color: textColor,
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.w600,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                showEntityBottomSheet(context, token);
              },
          ),
        );
      }
    }

    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(color: textColor, fontSize: 15),
    );
  }

  Widget _statusIcon(Color color) {
    if (message.isFailed) {
      return Icon(Icons.error_outline, size: 12, color: Colors.red.shade300);
    }
    if (message.type == 4 || message.type == 6) {
      // Outbox (Sending) or Queued
      return SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
      );
    }
    if (message.isDelivered) {
      return Icon(Icons.done_all, size: 12, color: color); // Delivered
    }
    return Icon(Icons.done, size: 12, color: color); // Sent but not delivered
  }
}
