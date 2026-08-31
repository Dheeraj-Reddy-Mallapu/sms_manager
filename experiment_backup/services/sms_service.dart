import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

class SmsService {
  final SmsQuery _query = SmsQuery();

  Future<bool> requestPermissions() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  Future<List<SmsMessage>> getRecentMessages({int limit = 200}) async {
    bool hasPermission = await requestPermissions();
    if (!hasPermission) {
      throw Exception('SMS permission not granted');
    }

    List<SmsMessage> allMessages = [];
    int currentStart = 0;
    const int fetchSize = 1000; // The library caps at 1000 per request

    while (allMessages.length < limit) {
      int remaining = limit - allMessages.length;
      int currentCount = remaining < fetchSize ? remaining : fetchSize;

      List<SmsMessage> chunk = await _query.querySms(
        kinds: [SmsQueryKind.inbox],
        start: currentStart,
        count: currentCount,
      );

      allMessages.addAll(chunk);

      // If the chunk is smaller than requested, we reached the end of the inbox
      if (chunk.length < currentCount) {
        break;
      }
      currentStart += chunk.length;
    }

    return allMessages;
  }
}
