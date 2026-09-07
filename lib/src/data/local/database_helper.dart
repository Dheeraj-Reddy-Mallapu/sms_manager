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
      version: 10,
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
  unreadCount INTEGER NOT NULL DEFAULT 0,
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
  subscriptionId INTEGER NOT NULL DEFAULT -1,
  status    INTEGER NOT NULL DEFAULT -1,
  embedding BLOB
)
''');

    await db.execute('''
CREATE VIRTUAL TABLE messages_fts USING fts4(
  content='messages',
  body, 
  address 
)
''');

    await db.execute('''
CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN
  INSERT INTO messages_fts(docid, body, address) VALUES (new.id, new.body, new.address);
END;
''');
    await db.execute('''
CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN
  DELETE FROM messages_fts WHERE docid = old.id;
END;
''');
    await db.execute('''
CREATE TRIGGER messages_au AFTER UPDATE ON messages BEGIN
  DELETE FROM messages_fts WHERE docid = old.id;
  INSERT INTO messages_fts(docid, body, address) VALUES (new.id, new.body, new.address);
END;
''');

    await db.execute('''
CREATE TABLE app_metadata (
  key       TEXT PRIMARY KEY,
  value     TEXT NOT NULL
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
    if (oldVersion < 4) {
      try {
        await db.execute(
          'ALTER TABLE threads ADD COLUMN unreadCount INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 5) {
      try {
        await db.execute('''
CREATE TABLE IF NOT EXISTS app_metadata (
  key       TEXT PRIMARY KEY,
  value     TEXT NOT NULL
)
''');
      } catch (_) {}
    }
    if (oldVersion < 6) {
      try {
        await db.execute(
          'ALTER TABLE messages ADD COLUMN status INTEGER NOT NULL DEFAULT -1',
        );
      } catch (_) {}
    }
    if (oldVersion < 10) {
      try {
        await db.execute('ALTER TABLE messages ADD COLUMN embedding BLOB');
      } catch (_) {}
      try {
        // Rebuild as fts4 because some OEMs lack fts5
        await db.execute('DROP TABLE IF EXISTS messages_fts');
        await db.execute('DROP TRIGGER IF EXISTS messages_ai');
        await db.execute('DROP TRIGGER IF EXISTS messages_ad');
        await db.execute('DROP TRIGGER IF EXISTS messages_au');

        await db.execute('''
CREATE VIRTUAL TABLE messages_fts USING fts4(
  content='messages',
  body, 
  address
)
''');
        await db.execute('''
INSERT INTO messages_fts(docid, body, address) 
SELECT id, body, address FROM messages
''');
        await db.execute('''
CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN
  INSERT INTO messages_fts(docid, body, address) VALUES (new.id, new.body, new.address);
END;
''');
        await db.execute('''
CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN
  DELETE FROM messages_fts WHERE docid = old.id;
END;
''');
        await db.execute('''
CREATE TRIGGER messages_au AFTER UPDATE ON messages BEGIN
  DELETE FROM messages_fts WHERE docid = old.id;
  INSERT INTO messages_fts(docid, body, address) VALUES (new.id, new.body, new.address);
END;
''');
      } catch (e) {
        print('FTS5 creation failed: $e');
      }
    }
  }

  // ── App Metadata ─────────────────────────────────────────────────────────

  Future<void> setMetadata(String key, String value) async {
    final db = await instance.database;
    await db.insert('app_metadata', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getMetadata(String key) async {
    final db = await instance.database;
    final maps = await db.query(
      'app_metadata',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] as String?;
    }
    return null;
  }

  Future<void> setFullSyncCompleted(bool completed) async {
    await setMetadata('full_sync_completed', completed ? 'true' : 'false');
  }

  Future<bool> getFullSyncCompleted() async {
    final val = await getMetadata('full_sync_completed');
    return val == 'true';
  }

  Future<void> setLastSyncTimestamp(int timestamp) async {
    await setMetadata('last_sync_timestamp', timestamp.toString());
  }

  Future<int> getLastSyncTimestamp() async {
    final val = await getMetadata('last_sync_timestamp');
    if (val != null) {
      return int.tryParse(val) ?? 0;
    }
    return 0;
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
    final sql = '''
      SELECT t.*, 
             CASE WHEN SUM(m.isStarred) > 0 THEN 1 ELSE 0 END as hasStarredMessages
      FROM threads t
      LEFT JOIN messages m ON t.id = m.threadId
      WHERE t.isBlocked = 0
      GROUP BY t.id
      ORDER BY t.date DESC
      LIMIT ? OFFSET ?
    ''';
    final maps = await db.rawQuery(sql, [limit, offset]);
    return maps.map((m) => SmsThread.fromMap(m)).toList();
  }

  Future<List<SmsThread>> getThreadsWithStarredMessages({
    int limit = 500,
    int offset = 0,
  }) async {
    final db = await instance.database;
    final sql = '''
      SELECT t.* 
      FROM threads t
      INNER JOIN messages m ON t.id = m.threadId
      WHERE t.isBlocked = 0 AND m.isStarred = 1
      GROUP BY t.id
      ORDER BY t.date DESC
      LIMIT ? OFFSET ?
    ''';
    final maps = await db.rawQuery(sql, [limit, offset]);
    return maps.map((m) => SmsThread.fromMap(m)).toList();
  }

  Future<SmsThread?> getThreadById(int threadId) async {
    final db = await instance.database;
    final maps = await db.query(
      'threads',
      where: 'id = ?',
      whereArgs: [threadId],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return SmsThread.fromMap(maps.first);
    }
    return null;
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

  Future<void> markAllAsRead() async {
    final db = await instance.database;
    await db.update('threads', {'read': 1}, where: 'read = 0');
    await db.update('messages', {'read': 1}, where: 'read = 0');
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
