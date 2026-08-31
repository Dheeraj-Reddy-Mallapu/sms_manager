import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';

/// Bottom sheet context menu shown on long-press of a message bubble.
class MessageContextMenu extends StatelessWidget {
  final SmsMessage message;
  final VoidCallback? onReply;
  final VoidCallback? onCopy;
  final VoidCallback? onForward;
  final VoidCallback? onStar;
  final VoidCallback? onDelete;
  final VoidCallback? onSelect;
  final VoidCallback? onDetails;

  const MessageContextMenu({
    super.key,
    required this.message,
    this.onReply,
    this.onCopy,
    this.onForward,
    this.onStar,
    this.onDelete,
    this.onSelect,
    this.onDetails,
  });

  static Future<void> show(
    BuildContext context, {
    required SmsMessage message,
    required VoidCallback onReply,
    required VoidCallback onCopy,
    required VoidCallback onForward,
    required VoidCallback onStar,
    required VoidCallback onDelete,
    required VoidCallback onSelect,
    required VoidCallback onDetails,
  }) {
    return showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => MessageContextMenu(
        message: message,
        onReply: onReply,
        onCopy: onCopy,
        onForward: onForward,
        onStar: onStar,
        onDelete: onDelete,
        onSelect: onSelect,
        onDetails: onDetails,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final preview = message.body.length > 80
        ? '${message.body.substring(0, 80)}…'
        : message.body;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Message preview
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              preview,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
        ),
        // Actions
        _tile(
          context,
          icon: Icons.reply_rounded,
          label: 'Reply',
          onTap: () {
            Navigator.pop(context);
            onReply?.call();
          },
        ),
        _tile(
          context,
          icon: Icons.copy_rounded,
          label: 'Copy',
          onTap: () {
            Clipboard.setData(ClipboardData(text: message.body));
            Navigator.pop(context);
            onCopy?.call();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        _tile(
          context,
          icon: Icons.forward_rounded,
          label: 'Forward',
          onTap: () {
            Navigator.pop(context);
            onForward?.call();
          },
        ),
        _tile(
          context,
          icon: message.isStarred
              ? Icons.star_rounded
              : Icons.star_border_rounded,
          label: message.isStarred ? 'Unstar' : 'Star',
          onTap: () {
            Navigator.pop(context);
            onStar?.call();
          },
        ),
        _tile(
          context,
          icon: Icons.check_circle_outline_rounded,
          label: 'Select',
          onTap: () {
            Navigator.pop(context);
            onSelect?.call();
          },
        ),
        _tile(
          context,
          icon: Icons.info_outline_rounded,
          label: 'Details',
          onTap: () {
            Navigator.pop(context);
            onDetails?.call();
          },
        ),
        _tile(
          context,
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          color: colorScheme.error,
          onTap: () {
            Navigator.pop(context);
            onDelete?.call();
          },
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.onSurface;
    return ListTile(
      leading: Icon(icon, color: effectiveColor),
      title: Text(label, style: TextStyle(color: effectiveColor)),
      dense: true,
      onTap: onTap,
    );
  }
}

/// Details bottom sheet — shows message metadata.
class MessageDetailsSheet extends StatelessWidget {
  final SmsMessage message;
  const MessageDetailsSheet({super.key, required this.message});

  static void show(BuildContext context, SmsMessage message) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => MessageDetailsSheet(message: message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final date = DateTime.fromMillisecondsSinceEpoch(message.date);
    final dateStr =
        '${date.day}/${date.month}/${date.year}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';

    final rows = [
      ('Message ID', message.id.toString()),
      ('From / To', message.address),
      ('Date', dateStr),
      ('Type', _typeName(message.type)),
      ('Read', message.read ? 'Yes' : 'No'),
      ('Starred', message.isStarred ? 'Yes' : 'No'),
      ('Length', '${message.body.length} characters'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Message Details',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      r.$1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.$2,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _typeName(int type) {
    switch (type) {
      case 1:
        return 'Inbox';
      case 2:
        return 'Sent';
      case 3:
        return 'Draft';
      case 4:
        return 'Outbox';
      case 5:
        return 'Failed';
      case 6:
        return 'Queued';
      default:
        return 'Unknown ($type)';
    }
  }
}
