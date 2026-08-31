import 'dart:async';

import 'package:sms_manager/src/data/local/database_helper.dart';
import 'package:sms_manager/src/data/models/sms_thread.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';
import 'package:sms_manager/src/services/native_sms_service.dart';

class SmsRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  // ── Incoming SMS stream ──────────────────────────────────────────
  // Dart side listens to this; HomeBloc subscribes and updates UI in real-time.
  Stream<Map<String, dynamic>> get incomingSmsStream =>
      NativeSmsService.incomingSmsStream;

  // ── Threads ──────────────────────────────────────────────────────

  /// Returns cached threads instantly, then refreshes from native in background.
  /// On very first open (empty DB) it waits for native fetch.
  Future<List<SmsThread>> getThreads({
    int limit = 500,
    int offset = 0,
    bool forceSync = false,
  }) async {
    if (forceSync) {
      // Hard refresh: fetch fresh, save, return
      return await _fetchAndCacheThreads(limit: limit, offset: offset);
    }

    final cached = await _db.getThreads(limit: limit, offset: offset);
    if (cached.isEmpty) {
      // First open — must wait
      return await _fetchAndCacheThreads(limit: limit, offset: offset);
    }
    // Return cached instantly; caller can trigger background refresh separately
    return cached;
  }

  /// Fetches from native (contacts are resolved inside SmsFetcher — no N calls),
  /// saves to SQLite, returns result.
  Future<List<SmsThread>> _fetchAndCacheThreads({
    int limit = 500,
    int offset = 0,
  }) async {
    // Note: contact lookup is now done INSIDE SmsFetcher.fetchThreads on the
    // Kotlin side, so nativeData already includes contactName & contactPhotoUri.
    final nativeData = await NativeSmsService.fetchThreads(
      limit: limit,
      offset: offset,
    );

    final threads = nativeData.map((raw) => SmsThread.fromMap(raw)).toList();

    if (threads.isNotEmpty) {
      await _db.upsertThreads(threads);
    }
    return threads;
  }

  /// Call this after returning cached threads to refresh in background.
  Future<List<SmsThread>> backgroundRefresh({int limit = 500}) async {
    return await _fetchAndCacheThreads(limit: limit);
  }

  // ── Messages ─────────────────────────────────────────────────────

  Future<List<SmsMessage>> getMessages(
    int threadId, {
    int limit = 200,
    int offset = 0,
    bool forceSync = false,
  }) async {
    if (!forceSync) {
      final cached = await _db.getMessages(
        threadId,
        limit: limit,
        offset: offset,
      );
      if (cached.isNotEmpty) return cached;
    }

    final nativeData = await NativeSmsService.fetchMessages(
      threadId,
      limit: limit,
      offset: offset,
    );
    final messages = nativeData.map((e) => SmsMessage.fromMap(e)).toList();

    if (messages.isNotEmpty) {
      await _db.insertMessages(messages);
    }
    return messages;
  }

  // ── Upsert single thread (e.g., after incoming SMS) ──────────────

  Future<void> upsertThreadFromIncomingSms(
    Map<String, dynamic> incomingEvent,
  ) async {
    // Re-fetch the thread that this SMS belongs to from native
    // (SmsFetcher will find it in content://sms)
    final allThreads = await NativeSmsService.fetchThreads(
      limit: 10,
      offset: 0,
    );
    final address = incomingEvent['address'] as String? ?? '';
    final matched = allThreads.where((t) {
      return (t['address'] as String? ?? '') == address;
    }).toList();
    if (matched.isNotEmpty) {
      final thread = SmsThread.fromMap(matched.first);
      await _db.upsertThread(thread);
    }
  }

  // ── Send / Mark / Delete ─────────────────────────────────────────

  Future<bool> sendSms(int threadId, String address, String body) async {
    final success = await NativeSmsService.sendSms(address, body);
    if (success) {
      final msg = SmsMessage(
        id: DateTime.now().millisecondsSinceEpoch,
        threadId: threadId,
        address: address,
        body: body,
        date: DateTime.now().millisecondsSinceEpoch,
        read: true,
        type: 2,
      );
      await _db.insertMessages([msg]);
    }
    return success;
  }

  Future<void> markThreadAsRead(int threadId) async {
    await NativeSmsService.markAsRead(threadId);
    await _db.markThreadRead(threadId);
  }

  Future<void> deleteMessageById(int messageId) async {
    await NativeSmsService.deleteMessage(messageId);
    await _db.deleteMessage(messageId);
  }

  Future<void> setMessageStarred(int messageId, {required bool starred}) async {
    await _db.setMessageStarred(messageId, starred: starred);
  }

  Future<void> deleteThread(int threadId) async {
    await _db.deleteThread(threadId);
  }
}
