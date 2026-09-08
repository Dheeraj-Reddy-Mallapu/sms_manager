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
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // ── FTS4 for full-text search over message bodies ─────────────────
      await db.execute('''
CREATE VIRTUAL TABLE messages_fts USING fts4(
  content='messages',
  body,
  address
)
''');
      // Populate existing messages into FTS
      await db.execute('INSERT INTO messages_fts(docid, body, address) SELECT id, body, address FROM messages;');

      // Auto-sync FTS index with messages table
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
    }
  }

  Future<void> _createDB(Database db, int version) async {
    // ── Threads ──────────────────────────────────────────────────────
    await db.execute('''
CREATE TABLE threads (
  id            INTEGER PRIMARY KEY,
  recipientIds  TEXT    NOT NULL DEFAULT '',
  address       TEXT    NOT NULL DEFAULT '',
  messageCount  INTEGER NOT NULL DEFAULT 0,
  snippet       TEXT    NOT NULL DEFAULT '',
  date          INTEGER NOT NULL DEFAULT 0,
  read          INTEGER NOT NULL DEFAULT 1,
  unreadCount   INTEGER NOT NULL DEFAULT 0,
  category      TEXT    NOT NULL DEFAULT '',
  contactName   TEXT,
  contactPhotoUri TEXT,
  isArchived    INTEGER NOT NULL DEFAULT 0,
  isMuted       INTEGER NOT NULL DEFAULT 0,
  isBlocked     INTEGER NOT NULL DEFAULT 0
)
''');

    // ── Messages ─────────────────────────────────────────────────────
    await db.execute('''
CREATE TABLE messages (
  id             INTEGER PRIMARY KEY,
  threadId       INTEGER NOT NULL,
  address        TEXT    NOT NULL DEFAULT '',
  body           TEXT    NOT NULL DEFAULT '',
  date           INTEGER NOT NULL DEFAULT 0,
  read           INTEGER NOT NULL DEFAULT 1,
  type           INTEGER NOT NULL DEFAULT 1,
  isStarred      INTEGER NOT NULL DEFAULT 0,
  subscriptionId INTEGER NOT NULL DEFAULT -1,
  status         INTEGER NOT NULL DEFAULT -1
)
''');

    // ── FTS4 for full-text search over message bodies ─────────────────
    await db.execute('''
CREATE VIRTUAL TABLE messages_fts USING fts4(
  content='messages',
  body,
  address
)
''');

    // Auto-sync FTS index with messages table
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
  }

  // ── Threads ──────────────────────────────────────────────────────────────

  Future<void> upsertThread(SmsThread thread) async {
    final db = await database;
    await db.insert(
      'threads',
      thread.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertThreads(List<SmsThread> threads) async {
    final db = await database;
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

  Future<List<SmsThread>> getThreads({int limit = 10000, int offset = 0}) async {
    final db = await database;
    final sql = '''
      SELECT t.*,
             CASE WHEN SUM(m.isStarred) > 0 THEN 1 ELSE 0 END AS hasStarredMessages
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

  Future<SmsThread?> getThreadById(int threadId) async {
    final db = await database;
    final maps = await db.query(
      'threads',
      where: 'id = ?',
      whereArgs: [threadId],
      limit: 1,
    );
    return maps.isNotEmpty ? SmsThread.fromMap(maps.first) : null;
  }

  Future<void> markThreadRead(int threadId) async {
    final db = await database;
    await db.update(
      'threads',
      {'read': 1, 'unreadCount': 0},
      where: 'id = ?',
      whereArgs: [threadId],
    );
    await db.update(
      'messages',
      {'read': 1},
      where: 'threadId = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> markAllAsRead() async {
    final db = await database;
    await db.update('threads', {'read': 1, 'unreadCount': 0}, where: 'read = 0');
    await db.update('messages', {'read': 1}, where: 'read = 0');
  }

  Future<void> updateThreadCategory(int threadId, String category) async {
    final db = await database;
    await db.update(
      'threads',
      {'category': category},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> setThreadBlocked(int threadId, {required bool blocked}) async {
    final db = await database;
    await db.update(
      'threads',
      {'isBlocked': blocked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> deleteThread(int threadId) async {
    final db = await database;
    await db.delete('threads', where: 'id = ?', whereArgs: [threadId]);
    await db.delete('messages', where: 'threadId = ?', whereArgs: [threadId]);
  }

  // ── Messages ─────────────────────────────────────────────────────────────

  Future<void> insertMessages(List<SmsMessage> messages) async {
    final db = await database;
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

  /// Returns messages ordered newest-first; caller reverses for display.
  Future<List<SmsMessage>> getMessages(
    int threadId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database;
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

  Future<int> getMessageCount(int threadId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM messages WHERE threadId = ?',
      [threadId],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<void> deleteMessage(int messageId) async {
    final db = await database;
    await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  Future<void> setMessageStarred(int messageId, {required bool starred}) async {
    final db = await database;
    await db.update(
      'messages',
      {'isStarred': starred ? 1 : 0},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
