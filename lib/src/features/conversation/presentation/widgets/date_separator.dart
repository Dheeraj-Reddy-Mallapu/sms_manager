import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

class DateSeparator extends StatelessWidget {
  final DateTime date;

  const DateSeparator({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = _label(date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Divider(color: colorScheme.outlineVariant, thickness: 0.5),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(color: colorScheme.outlineVariant, thickness: 0.5),
          ),
        ],
      ),
    );
  }

  String _label(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(msgDay).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(date); // "Tuesday"
    if (date.year == now.year) {
      return DateFormat('MMMM d').format(date); // "August 24"
    }
    return DateFormat('MMMM d, y').format(date); // "August 24, 2023"
  }
}

/// "── New Messages ──" separator shown above first unread message on open.
class UnreadSeparator extends StatelessWidget {
  const UnreadSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: colorScheme.primary.withAlpha(120),
              thickness: 0.8,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'New Messages',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              color: colorScheme.primary.withAlpha(120),
              thickness: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
