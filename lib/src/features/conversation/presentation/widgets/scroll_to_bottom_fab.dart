import 'package:material_ui/material_ui.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';

class ScrollToBottomFab extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const ScrollToBottomFab({
    super.key,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 16, bottom: 8),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(40),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(10),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 24,
            ),
            if (unreadCount > 0)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: TextStyle(
                      color: colorScheme.onError,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Displays a quoted reply banner above the compose bar.
class ReplyBanner extends StatelessWidget {
  final SmsMessage message;
  final VoidCallback onDismiss;

  const ReplyBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOut = message.isOutgoing;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          left: BorderSide(
            color: isOut ? colorScheme.primary : colorScheme.tertiary,
            width: 3,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isOut ? 'You' : 'Them',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isOut ? colorScheme.primary : colorScheme.tertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.body,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}
