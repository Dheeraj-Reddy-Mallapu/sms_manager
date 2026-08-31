import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sms_manager/src/data/models/sms_thread.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('sms_manager.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE threads (
  id          INTEGER PRIMARY KEY,
  recipientIds TEXT NOT NULL,
  address     TEXT NOT NULL,
  messageCount INTEGER NOT NULL,
  snippet     TEXT NOT NULL,
  date        INTEGER NOT NULL,
  read        INTEGER NOT NULL,
  category    TEXT NOT NULL,
  contactName TEXT,
  contactPhotoUri TEXT,
  isArchived  INTEGER NOT NULL DEFAULT 0,
  isMuted     INTEGER NOT NULL DEFAULT 0,
  isBlocked   INTEGER NOT NULL DEFAULT 0
)
''');

    await db.execute('''
CREATE TABLE messages (
  id        INTEGER PRIMARY KEY,
  threadId  INTEGER NOT NULL,
  address   TEXT NOT NULL,
  body      TEXT NOT NULL,
  date      INTEGER NOT NULL,
  read      INTEGER NOT NULL,
  type      INTEGER NOT NULL,
  isStarred INTEGER NOT NULL DEFAULT 0,
  subscriptionId INTEGER NOT NULL DEFAULT -1
)
''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new columns safely
      try {
        await db.execute(
          'ALTER TABLE messages ADD COLUMN isStarred INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE threads ADD COLUMN isArchived INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE threads ADD COLUMN isMuted INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE threads ADD COLUMN isBlocked INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
          'ALTER TABLE messages ADD COLUMN subscriptionId INTEGER NOT NULL DEFAULT -1',
        );
      } catch (_) {}
    }
  }

  // ── Threads ──────────────────────────────────────────────────────────────

  Future<void> insertThread(SmsThread thread) async {
    final db = await instance.database;
    await db.insert(
      'threads',
      thread.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertThread(SmsThread thread) => insertThread(thread);

  Future<void> insertThreads(List<SmsThread> threads) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final t in threads) {
      batch.insert(
        'threads',
        t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsertThreads(List<SmsThread> threads) => insertThreads(threads);

  Future<List<SmsThread>> getThreads({int limit = 500, int offset = 0}) async {
    final db = await instance.database;
    final maps = await db.query(
      'threads',
      where: 'isBlocked = 0',
      orderBy: 'date DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => SmsThread.fromMap(m)).toList();
  }

  Future<void> markThreadRead(int threadId) async {
    final db = await instance.database;
    await db.update(
      'threads',
      {'read': 1},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> updateThreadCategory(int threadId, String category) async {
    final db = await instance.database;
    await db.update(
      'threads',
      {'category': category},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> setThreadArchived(int threadId, {required bool archived}) async {
    final db = await instance.database;
    await db.update(
      'threads',
      {'isArchived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> setThreadBlocked(int threadId, {required bool blocked}) async {
    final db = await instance.database;
    await db.update(
      'threads',
      {'isBlocked': blocked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> deleteThread(int threadId) async {
    final db = await instance.database;
    await db.delete('threads', where: 'id = ?', whereArgs: [threadId]);
    await db.delete('messages', where: 'threadId = ?', whereArgs: [threadId]);
  }

  Future<void> clearThreads() async {
    final db = await instance.database;
    await db.delete('threads');
  }

  // ── Messages ─────────────────────────────────────────────────────────────

  Future<void> insertMessages(List<SmsMessage> messages) async {
    final db = await instance.database;
    final batch = db.batch();
    for (final m in messages) {
      batch.insert(
        'messages',
        m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Returns messages ordered newest-first (DESC), caller reverses for display.
  Future<List<SmsMessage>> getMessages(
    int threadId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await instance.database;
    final maps = await db.query(
      'messages',
      where: 'threadId = ?',
      whereArgs: [threadId],
      orderBy: 'date DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => SmsMessage.fromMap(m)).toList();
  }

  Future<void> deleteMessage(int messageId) async {
    final db = await instance.database;
    await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  Future<void> setMessageStarred(int messageId, {required bool starred}) async {
    final db = await instance.database;
    await db.update(
      'messages',
      {'isStarred': starred ? 1 : 0},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Returns the count of messages cached for a thread (used to detect hasMore).
  Future<int> getMessageCount(int threadId) async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM messages WHERE threadId = ?',
      [threadId],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
