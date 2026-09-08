import 'package:intl/intl.dart';

class DateFormatter {
  static String formatShortDate(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final diff = now.difference(date).inDays;

    if (diff == 0) return DateFormat.jm().format(date); // "10:38 AM"
    if (diff < 7) return DateFormat('EEEE').format(date); // "Tuesday"
    if (date.year == now.year) return DateFormat('MMM d').format(date); // "Aug 24"
    return DateFormat('MM/dd/yy').format(date); // "08/24/23"
  }

  static String formatTimelineDate(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    final diff = now.difference(date).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(date); // "Tuesday"
    if (date.year == now.year) return DateFormat('MMMM d').format(date); // "August 24"
    return DateFormat('MMMM d, y').format(date); // "August 24, 2023"
  }
  
  static String formatDetailedDate(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return DateFormat('d MMM yyyy · h:mm:ss a').format(date);
  }
}
