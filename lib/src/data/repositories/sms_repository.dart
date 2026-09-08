import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sms_manager/src/data/local/database_helper.dart';
import 'package:sms_manager/src/data/models/sms_thread.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';
import 'package:sms_manager/src/services/native_sms_service.dart';
import 'package:sms_manager/src/services/sms_classifier.dart';

class SmsRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  static const _keyFullSyncDone = 'full_sync_completed';
  static const _keyLastSyncTs = 'last_sync_timestamp';

  // ── Metadata (SharedPreferences) ─────────────────────────────────────────

  Future<bool> getFullSyncCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFullSyncDone) ?? false;
  }

  Future<void> setFullSyncCompleted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFullSyncDone, value);
  }

  Future<int> getLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyLastSyncTs) ?? 0;
  }

  Future<void> setLastSyncTimestamp(int timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastSyncTs, timestamp);
  }

  // ── Incoming SMS stream ──────────────────────────────────────────────────
  Stream<Map<String, dynamic>> get incomingSmsStream =>
      NativeSmsService.incomingSmsStream;

  // ── System SMS changes ────────────────────────────────────────────────────
  Stream<void> get systemSmsChanges => NativeSmsService.systemSmsChanges;

  // ── Threads ───────────────────────────────────────────────────────────────

  Future<List<SmsThread>> getThreads({
    int limit = 10000,
    int offset = 0,
    bool forceSync = false,
  }) async {
    if (forceSync) {
      return await _fetchAndCacheThreads(limit: limit, offset: offset);
    }
    final cached = await _db.getThreads(limit: limit, offset: offset);
    return cached;
  }

  Future<List<SmsThread>> _fetchAndCacheThreads({
    int limit = 10000,
    int offset = 0,
  }) async {
    final nativeData = await NativeSmsService.fetchThreads(
      limit: limit,
      offset: offset,
    );
    final threads = nativeData.map((raw) {
      final thread = SmsThread.fromMap(raw);
      final category = SmsClassifier.classify(
        address: thread.address,
        body: thread.snippet,
        contactName: thread.contactName,
      );
      return thread.copyWith(
        category: category.isNotEmpty ? category : 'Updates',
      );
    }).toList();
    if (threads.isNotEmpty) {
      await _db.upsertThreads(threads);
    }
    return threads;
  }

  Future<List<SmsThread>> backgroundRefresh({
    int limit = 10000,
    int offset = 0,
  }) async {
    return await _fetchAndCacheThreads(limit: limit, offset: offset);
  }

  Future<void> smartSync({int maxLimit = 10000, int chunkSize = 100}) async {
    await for (final _ in syncThreadsPaginated(
      maxLimit: maxLimit,
      chunkSize: chunkSize,
    )) {}
  }

  Stream<List<SmsThread>> syncThreadsPaginated({
    int maxLimit = 10000,
    int chunkSize = 100,
  }) async* {
    final fullSyncCompleted = await getFullSyncCompleted();

    if (!fullSyncCompleted) {
      // ── First launch: full paginated sync ──────────────────────────────
      try {
        for (int offset = 0; offset < maxLimit; offset += chunkSize) {
          final chunk = await _fetchAndCacheThreads(
            limit: chunkSize,
            offset: offset,
          );
          yield await _db.getThreads(limit: maxLimit);
          if (chunk.length < chunkSize) break;
        }

        await setFullSyncCompleted(true);

        final cached = await _db.getThreads(limit: 1);
        if (cached.isNotEmpty) {
          await setLastSyncTimestamp(cached.first.date);
        }

        // Background message fetch for full-text search
        Future.microtask(() async {
          try {
            int msgOffset = 0;
            while (true) {
              final msgsRaw = await NativeSmsService.fetchAllMessages(
                limit: 500,
                offset: msgOffset,
              );
              if (msgsRaw.isEmpty) break;
              final msgs = msgsRaw.map((e) => SmsMessage.fromMap(e)).toList();
              await _db.insertMessages(msgs);
              msgOffset += 500;
            }
          } catch (_) {}
        });
      } catch (_) {
        // Leave full_sync_completed false so we retry next launch
      }
    } else {
      // ── Subsequent launches: delta sync ────────────────────────────────
      final lastSync = await getLastSyncTimestamp();
      try {
        final nativeData = await NativeSmsService.fetchThreadsSince(lastSync);
        final threads = nativeData.map((raw) {
          final thread = SmsThread.fromMap(raw);
          final category = SmsClassifier.classify(
            address: thread.address,
            body: thread.snippet,
            contactName: thread.contactName,
          );
          return thread.copyWith(
            category: category.isNotEmpty ? category : 'Updates',
          );
        }).toList();

        if (threads.isNotEmpty) {
          await _db.upsertThreads(threads);
          int maxDate = lastSync;
          for (final t in threads) {
            if (t.date > maxDate) maxDate = t.date;
          }
          await setLastSyncTimestamp(maxDate);
        }

        // Recovery: re-fetch messages if messages table is sparse
        final msgCount =
            Sqflite.firstIntValue(
              await _db.database.then(
                (db) => db.rawQuery('SELECT COUNT(*) FROM messages'),
              ),
            ) ??
            0;
        final threadCount =
            Sqflite.firstIntValue(
              await _db.database.then(
                (db) => db.rawQuery('SELECT COUNT(*) FROM threads'),
              ),
            ) ??
            0;

        if (msgCount < threadCount) {
          Future.microtask(() async {
            try {
              int msgOffset = 0;
              while (true) {
                final msgsRaw = await NativeSmsService.fetchAllMessages(
                  limit: 500,
                  offset: msgOffset,
                );
                if (msgsRaw.isEmpty) break;
                final msgs = msgsRaw.map((e) => SmsMessage.fromMap(e)).toList();
                await _db.insertMessages(msgs);
                msgOffset += 500;
              }
            } catch (_) {}
          });
        }
      } catch (_) {}

      yield await _db.getThreads(limit: maxLimit);
    }
  }

  // ── SIM Info ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSimInfo() async {
    return await NativeSmsService.getSimInfo();
  }

  // ── Messages ──────────────────────────────────────────────────────────────

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

  Future<void> upsertThreadFromIncomingSms(
    Map<String, dynamic> incomingEvent,
  ) async {
    final allThreads = await NativeSmsService.fetchThreads(
      limit: 10,
      offset: 0,
    );
    final address = incomingEvent['address'] as String? ?? '';
    final matched = allThreads.where((t) {
      return (t['address'] as String? ?? '') == address;
    }).toList();
    if (matched.isNotEmpty) {
      var thread = SmsThread.fromMap(matched.first);
      final category = SmsClassifier.classify(
        address: thread.address,
        body: thread.snippet,
        contactName: thread.contactName,
      );
      thread = thread.copyWith(
        category: category.isNotEmpty ? category : 'Updates',
      );
      await _db.upsertThread(thread);
    }
  }

  // ── Send / Mark / Delete ──────────────────────────────────────────────────

  Future<bool> sendSms(
    int threadId,
    String address,
    String body, {
    int? subscriptionId,
  }) async {
    int nativeId = -1;
    try {
      nativeId = await NativeSmsService.sendSms(
        address,
        body,
        subscriptionId: subscriptionId,
      );
    } catch (_) {}

    if (nativeId > 0) {
      final msg = SmsMessage(
        id: nativeId,
        threadId: threadId,
        address: address,
        body: body,
        date: DateTime.now().millisecondsSinceEpoch,
        read: true,
        type: 4, // Outbox
        subscriptionId: subscriptionId ?? -1,
      );
      await _db.insertMessages([msg]);
      return true;
    }
    return false;
  }

  Future<void> markThreadAsRead(int threadId) async {
    await NativeSmsService.markAsRead(threadId);
    await _db.markThreadRead(threadId);
  }

  Future<void> markAllAsRead() async {
    await NativeSmsService.markAllAsRead();
    await _db.markAllAsRead();
  }

  Future<void> deleteMessageById(int messageId) async {
    await NativeSmsService.deleteMessage(messageId);
    await _db.deleteMessage(messageId);
  }

  Future<void> setMessageStarred(int messageId, {required bool starred}) async {
    await _db.setMessageStarred(messageId, starred: starred);
  }

  Future<void> deleteThread(int threadId) async {
    await NativeSmsService.deleteThread(threadId);
    await _db.deleteThread(threadId);
  }
}
