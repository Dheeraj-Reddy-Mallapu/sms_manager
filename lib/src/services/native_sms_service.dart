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

  // ── Default SMS App ──────────────────────────────────────────────

  static Future<bool> isDefaultSmsApp() async {
    try {
      return await _roleChannel.invokeMethod<bool>('isDefaultSmsApp') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestDefaultSmsRole() async {
    try {
      await _roleChannel.invokeMethod('requestDefaultSmsRole');
    } catch (_) {}
  }

  // ── Threads ──────────────────────────────────────────────────────

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

  // ── Send SMS ─────────────────────────────────────────────────────

  static Future<bool> sendSms(String address, String body) async {
    try {
      return await _queryChannel.invokeMethod<bool>('sendSms', {
            'address': address,
            'body': body,
          }) ??
          false;
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
