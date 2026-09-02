import 'package:flutter/services.dart';

class NativeSmsService {
  static const _roleChannel = MethodChannel('sms_manager/default_role');
  static const _queryChannel = MethodChannel('sms_manager/query');
  static const _incomingChannel = EventChannel('sms_manager/incoming');

  // ── Singleton stream for incoming SMS (from BroadcastReceiver) ──
  static Stream<Map<String, dynamic>>? _incomingStream;

  static Stream<Map<String, dynamic>> get incomingSmsStream {
    _incomingStream ??= _incomingChannel.receiveBroadcastStream().map(
      (event) => Map<String, dynamic>.from(event as Map),
    );
    return _incomingStream!;
  }

  // ── Singleton stream for DB system changes ──
  static const _systemChangesChannel = EventChannel(
    'sms_manager/system_changes',
  );
  static Stream<void>? _systemChangesStream;

  static Stream<void> get systemSmsChanges {
    _systemChangesStream ??= _systemChangesChannel.receiveBroadcastStream().map(
      (_) {},
    );
    return _systemChangesStream!;
  }

  // ── Default SMS App ──────────────────────────────────────────────

  static Future<bool> isDefaultSmsApp() async {
    try {
      return await _roleChannel.invokeMethod<bool>('isDefaultSmsApp') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestDefaultSmsRole() async {
    try {
      return await _roleChannel.invokeMethod<bool>('requestDefaultSmsRole') ??
          false;
    } catch (_) {
      return false;
    }
  }

  // ── Threads ──────────────────────────────────────────────────────

  static Future<void> setActiveThread(int? threadId) async {
    try {
      await _queryChannel.invokeMethod('setActiveThread', {
        'threadId': threadId,
      });
    } catch (_) {}
  }

  static Future<int?> getOrCreateThreadId(String address) async {
    try {
      final id = await _queryChannel.invokeMethod('getOrCreateThreadId', {
        'address': address,
      });
      // Depending on Kotlin result, it might be an int or a string that parses to int, or a Long in Kotlin which is int in Dart.
      if (id is int) return id;
      if (id is String) return int.tryParse(id);
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Contacts ──────────────────────────────────────────────────────

  static Future<List<Map<String, String>>> searchContacts(String query) async {
    try {
      final List<dynamic>? result = await _queryChannel.invokeMethod(
        'searchContacts',
        {'query': query},
      );
      if (result == null) return [];
      return result.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches thread summaries. Contact lookup is done natively inside
  /// SmsFetcher (no per-thread MethodChannel round trips).
  static Future<List<Map<String, dynamic>>> fetchThreads({
    int limit = 500,
    int offset = 0,
  }) async {
    try {
      final List<dynamic> result = await _queryChannel.invokeMethod(
        'fetchThreads',
        {'limit': limit, 'offset': offset},
      );
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      throw Exception('Error fetching threads: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> fetchThreadsSince(
    int timestamp, {
    int limit = 1000,
  }) async {
    try {
      final List<dynamic> result = await _queryChannel.invokeMethod(
        'fetchThreadsSince',
        {'timestamp': timestamp, 'limit': limit},
      );
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      throw Exception('Error fetching threads since: $e');
    }
  }

  // ── Messages ─────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchMessages(
    int threadId, {
    int limit = 200,
    int offset = 0,
  }) async {
    try {
      final List<dynamic> result = await _queryChannel.invokeMethod(
        'fetchMessages',
        {'threadId': threadId, 'limit': limit, 'offset': offset},
      );
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      throw Exception('Error fetching messages: $e');
    }
  }

  // ── SIM Info ─────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getSimInfo() async {
    try {
      final List<dynamic>? result = await _queryChannel.invokeMethod(
        'getSimInfo',
      );
      if (result == null) return [];
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Send SMS ─────────────────────────────────────────────────────

  static Future<int> sendSms(
    String address,
    String body, {
    int? subscriptionId,
  }) async {
    try {
      return await _queryChannel.invokeMethod<int>('sendSms', {
            'address': address,
            'body': body,
            'subscriptionId': subscriptionId,
          }) ??
          -1;
    } catch (e) {
      throw Exception('Error sending SMS: $e');
    }
  }

  // ── Mark as Read ─────────────────────────────────────────────────

  static Future<bool> markAsRead(int threadId) async {
    try {
      return await _queryChannel.invokeMethod<bool>('markAsRead', {
            'threadId': threadId,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  // ── Delete Message ───────────────────────────────────────────────

  static Future<bool> deleteMessage(int messageId) async {
    try {
      return await _queryChannel.invokeMethod<bool>('deleteMessage', {
            'messageId': messageId,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  // ── Contact lookup (single, kept for compatibility) ──────────────

  static Future<Map<String, dynamic>?> getContactByAddress(
    String address,
  ) async {
    try {
      final result = await _queryChannel.invokeMethod<Map>(
        'getContactByAddress',
        {'address': address},
      );
      return result != null ? Map<String, dynamic>.from(result) : null;
    } catch (_) {
      return null;
    }
  }
}
