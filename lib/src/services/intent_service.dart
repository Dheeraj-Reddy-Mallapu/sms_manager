import 'package:flutter/services.dart';
import 'package:sms_manager/src/core/routing/app_router.dart';
import 'package:sms_manager/src/services/native_sms_service.dart';

class IntentService {
  static const _channel = EventChannel('sms_manager/intent');

  static void initialize() {
    _channel.receiveBroadcastStream().listen((event) async {
      if (event is Map) {
        final address = event['address'] as String?;
        final body = event['body'] as String?;

        if (address != null && address.isNotEmpty) {
          // It's a SENDTO or VIEW intent with a specific number
          final threadId = await NativeSmsService.getOrCreateThreadId(address);
          if (threadId != null) {
            appRouter.push(
              '/home/conversation/$threadId',
              extra: {'thread': null, 'initialBody': body},
            );
          } else {
            // Fallback to compose page if thread creation failed somehow
            appRouter.push('/home/compose', extra: body);
          }
        } else if (body != null && body.isNotEmpty) {
          // It's a SEND intent (Share sheet) with just text
          appRouter.push('/home/compose', extra: body);
        }
      }
    });
  }
}
