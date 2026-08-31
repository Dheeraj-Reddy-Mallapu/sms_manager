import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';

/// Unified bottom sheet: full selectable text + action chips + inline message details.
class MessageSheet extends StatefulWidget {
  final SmsMessage message;
  final VoidCallback? onCopy;
  final VoidCallback? onForward;
  final VoidCallback? onStar;
  final VoidCallback? onDelete;
  final VoidCallback? onSelect;

  const MessageSheet({
    super.key,
    required this.message,
    this.onCopy,
    this.onForward,
    this.onStar,
    this.onDelete,
    this.onSelect,
  });

  static Future<void> show(
    BuildContext context, {
    required SmsMessage message,
    required VoidCallback onCopy,
    required VoidCallback onForward,
    required VoidCallback onStar,
    required VoidCallback onDelete,
    required VoidCallback onSelect,
  }) {
    return showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => MessageSheet(
        message: message,
        onCopy: onCopy,
        onForward: onForward,
        onStar: onStar,
        onDelete: onDelete,
        onSelect: onSelect,
      ),
    );
  }

  @override
  State<MessageSheet> createState() => _MessageSheetState();
}

class _MessageSheetState extends State<MessageSheet> {
  static const _channel = MethodChannel('sms_manager/query');
  List<Map<String, dynamic>> _simInfoList = [];

  @override
  void initState() {
    super.initState();
    _fetchSimInfo();
  }

  Future<void> _fetchSimInfo() async {
    try {
      final result = await _channel.invokeListMethod<Map>('getSimInfo');
      if (mounted && result != null) {
        setState(() {
          _simInfoList = result
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
    } catch (_) {}
  }

  String _resolveSimLabel() {
    final subId = widget.message.subscriptionId;
    if (subId == -1) return 'Unknown';
    final match = _simInfoList
        .where((s) => s['subscriptionId'] == subId)
        .firstOrNull;
    if (match == null) return 'SIM (ID $subId)';
    final slot = (match['simSlotIndex'] as int?) ?? 0;
    final name = match['displayName'] as String? ?? 'SIM ${slot + 1}';
    final number = match['number'] as String? ?? '';
    return number.isNotEmpty ? '$name · $number' : name;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.88;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 20,
          right: 20,
          top: 4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Full message body ─────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: _buildSelectableBody(colorScheme),
            ),

            const SizedBox(height: 16),

            // ── Action chips ──────────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _actionChip(
                    context,
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.message.body),
                      );
                      Navigator.pop(context);
                      widget.onCopy?.call();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  _actionChip(
                    context,
                    icon: widget.message.isStarred
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    label: widget.message.isStarred ? 'Unstar' : 'Star',
                    onTap: () {
                      Navigator.pop(context);
                      widget.onStar?.call();
                    },
                  ),
                  _actionChip(
                    context,
                    icon: Icons.forward_rounded,
                    label: 'Forward',
                    onTap: () {
                      Navigator.pop(context);
                      widget.onForward?.call();
                    },
                  ),
                  _actionChip(
                    context,
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Select',
                    onTap: () {
                      Navigator.pop(context);
                      widget.onSelect?.call();
                    },
                  ),
                  _actionChip(
                    context,
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    isDestructive: true,
                    onTap: () {
                      Navigator.pop(context);
                      widget.onDelete?.call();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Message details ───────────────────────────────────────────
            _detailsSection(context, colorScheme),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectableBody(ColorScheme colorScheme) {
    final body = widget.message.body;
    final pattern = RegExp(
      r'(https?://[^\s]+)|(www\.[^\s]+)|(\+?[0-9][\d\s\-(]{7,}[0-9])|([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})',
    );
    final matches = pattern.allMatches(body);
    final textColor = colorScheme.onSurface;

    if (matches.isEmpty) {
      return SelectableText(
        body,
        style: TextStyle(color: textColor, fontSize: 15, height: 1.45),
      );
    }

    final spans = <TextSpan>[];
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
            color: colorScheme.primary,
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

    return SelectableText.rich(
      TextSpan(
        children: spans,
        style: TextStyle(color: textColor, fontSize: 15, height: 1.45),
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
      final digits = raw.replaceAll(RegExp(r'[\s\-()]'), '');
      uri = Uri.tryParse('tel:$digits');
    }
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _detailsSection(BuildContext context, ColorScheme colorScheme) {
    final message = widget.message;
    final date = DateTime.fromMillisecondsSinceEpoch(message.date);
    final dateStr = DateFormat('d MMM yyyy · h:mm:ss a').format(date);
    final parts = _computeSmsPartCount(message.body);
    final lengthLabel = '${message.body.length} chars · $parts SMS';

    final rows = <MapEntry<String, String>>[
      if (!message.isOutgoing) ...[
        MapEntry('From', message.address),
        MapEntry('Received on', _resolveSimLabel()),
      ] else ...[
        MapEntry('To', message.address),
        MapEntry('Sent from', _resolveSimLabel()),
      ],
      MapEntry('Date', dateStr),
      MapEntry('Type', _typeName(message.type)),
      MapEntry('Read', message.read ? 'Yes' : 'No'),
      MapEntry('Length', lengthLabel),
      if (message.isStarred) const MapEntry('Starred', 'Yes'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: colorScheme.outlineVariant, height: 1),
        const SizedBox(height: 12),
        Text(
          'Message Details',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...rows.map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    e.key,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    e.value,
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
    );
  }

  Widget _actionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final color =
        isDestructive ? colorScheme.error : colorScheme.onSurface;
    final bg = isDestructive
        ? colorScheme.errorContainer.withAlpha(80)
        : colorScheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _computeSmsPartCount(String body) {
    if (body.isEmpty) return 1;
    if (body.length <= 160) return 1;
    return ((body.length - 1) ~/ 153) + 1;
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
