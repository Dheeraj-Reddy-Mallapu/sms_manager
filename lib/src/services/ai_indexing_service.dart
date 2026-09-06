import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:bert_tokenizer/bert_tokenizer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sms_manager/src/data/local/database_helper.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';
import 'package:sqflite/sqflite.dart';

class SearchRequest {
  final String query;
  final List<String> filters;
  final SendPort replyTo;

  SearchRequest(this.query, this.filters, this.replyTo);
}

class AiProgress {
  final bool isIndexing;
  final int completed;
  final int total;
  AiProgress(this.isIndexing, this.completed, this.total);
}

class AiIndexingService {
  static final AiIndexingService _instance = AiIndexingService._internal();
  static AiIndexingService get instance => _instance;

  AiIndexingService._internal();

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  bool _isIsolateRunning = false;
  bool _isIndexing = false; // Tracks if batch processing is currently running

  // Stream to expose indexing progress
  final _progressController = StreamController<AiProgress>.broadcast();
  Stream<AiProgress> get progressStream => _progressController.stream;

  Future<void> _emitProgress() async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;
      final counts = await db.rawQuery(
        'SELECT (SELECT COUNT(*) FROM messages) as total, (SELECT COUNT(*) FROM messages WHERE embedding IS NULL) as unindexed',
      );
      if (counts.isNotEmpty) {
        int total = (counts.first['total'] as int?) ?? 0;
        int unindexed = (counts.first['unindexed'] as int?) ?? 0;
        _progressController.add(
          AiProgress(_isIndexing, total - unindexed, total),
        );
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> initializeAndStartIndexing() async {
    if (_isIsolateRunning) {
      if (!_isIndexing) {
        _isIndexing = true;
        _sendPort?.send('start_batch');
        _emitProgress();
      }
      return;
    }
    _isIsolateRunning = true;
    _isIndexing = true;
    _emitProgress();

    try {
      // 1. Copy assets to device storage (so isolate can read them)
      final docs = await getApplicationDocumentsDirectory();

      final modelFile = File(join(docs.path, 'nihal-minilm.tflite'));
      if (!await modelFile.exists()) {
        final byteData = await rootBundle.load('assets/nihal-minilm.tflite');
        await modelFile.writeAsBytes(
          byteData.buffer.asUint8List(),
          flush: true,
        );
      }

      final vocabContent = await rootBundle.loadString('assets/vocab.txt');

      // 2. Spawn Isolate
      final rootToken = RootIsolateToken.instance!;
      _receivePort?.close();
      _receivePort = ReceivePort();

      _isolate = await Isolate.spawn(
        _indexingIsolateEntryPoint,
        _IsolateInitData(
          sendPort: _receivePort!.sendPort,
          modelPath: modelFile.path,
          vocabContent: vocabContent,
          dbPath: join(await getDatabasesPath(), 'sms_manager.db'),
          rootIsolateToken: rootToken,
        ),
      );

      // 3. Listen for messages
      _receivePort!.listen((message) {
        if (message is SendPort) {
          _sendPort = message;
          // Trigger the first batch
          _sendPort?.send('start_batch');
          _emitProgress();
        } else if (message == 'batch_done') {
          // Trigger the next batch
          _sendPort?.send('start_batch');
          _emitProgress();
        } else if (message == 'all_done') {
          _isIndexing = false;
          _emitProgress();
          // Keep isolate alive for searches! Do not kill it.
        } else if (message is String && message.startsWith('error:')) {
          print('AI Indexing error: $message');
        }
      });
    } catch (e) {
      _isIsolateRunning = false;
      _isIndexing = false;
      _emitProgress();
      print('AI Indexing failed to start: $e');
    }
  }

  void _stopIsolate() {
    _sendPort?.send('stop');
    _isolate = null;
    _sendPort = null;
    _receivePort?.close();
    _receivePort = null;
    _isIsolateRunning = false;
    _isIndexing = false;
    _emitProgress();
  }

  /// Called when new SMS arrives to re-trigger indexing
  void triggerIndexing() {
    if (!_isIsolateRunning) {
      initializeAndStartIndexing();
    } else if (!_isIndexing) {
      _isIndexing = true;
      _sendPort?.send('start_batch');
      _emitProgress();
    }
  }

  /// Perform a hybrid search
  Future<List<SmsMessage>> search(
    String query, [
    List<String> filters = const [],
  ]) async {
    if (!_isIsolateRunning || _sendPort == null) {
      // If service isn't running, start it
      await initializeAndStartIndexing();
      // Wait up to 3 seconds for isolate to spin up and return the sendPort
      for (int i = 0; i < 30; i++) {
        if (_sendPort != null) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (_sendPort == null) return [];

    final completer = Completer<List<SmsMessage>>();
    final replyPort = ReceivePort();

    replyPort.listen((data) {
      if (!completer.isCompleted) {
        if (data is List) {
          try {
            completer.complete(
              data
                  .map((m) => SmsMessage.fromMap(m.cast<String, dynamic>()))
                  .toList(),
            );
          } catch (e) {
            print('Search error mapping: $e');
            completer.complete([]);
          }
        } else {
          completer.complete([]);
        }
      }
      replyPort.close();
    });

    _sendPort?.send(SearchRequest(query, filters, replyPort.sendPort));
    return completer.future;
  }
}

class _IsolateInitData {
  final SendPort sendPort;
  final String modelPath;
  final String vocabContent;
  final String dbPath;
  final RootIsolateToken rootIsolateToken;

  _IsolateInitData({
    required this.sendPort,
    required this.modelPath,
    required this.vocabContent,
    required this.dbPath,
    required this.rootIsolateToken,
  });
}

// ---------------------------------------------------------
// ISOLATE ENTRY POINT
// ---------------------------------------------------------

void _indexingIsolateEntryPoint(_IsolateInitData initData) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(initData.rootIsolateToken);

  final receivePort = ReceivePort();
  initData.sendPort.send(receivePort.sendPort);

  // Initialize DB
  final dbHelper = DatabaseHelper.instance;

  // Initialize AI Model
  Interpreter? interpreter;
  BertTokenizer? tokenizer;

  try {
    final options = InterpreterOptions();
    options.addDelegate(
      XNNPackDelegate(options: XNNPackDelegateOptions(numThreads: 4)),
    );
    interpreter = Interpreter.fromFile(File(initData.modelPath), options: options);
    
    // Explicitly allocate tensors to avoid reallocation overhead on each inference
    for (int i = 0; i < interpreter!.getInputTensors().length; i++) {
      interpreter!.resizeInputTensor(i, [1, 128]);
    }
    interpreter!.allocateTensors();

    tokenizer = BertTokenizer.fromStringContent(initData.vocabContent);
  } catch (e) {
    initData.sendPort.send('error: Failed to initialize AI in isolate: $e');
    initData.sendPort.send('all_done');
    return;
  }

  // Pre-allocate tensors
  final inputIdsArray = List.generate(1, (i) => List<int>.filled(128, 0));
  final attentionMaskArray = List.generate(1, (i) => List<int>.filled(128, 0));
  final outputArray = List.generate(1, (i) => List<double>.filled(384, 0.0));

  bool isProcessing = false;

  receivePort.listen((message) async {
    if (message == 'stop') {
      interpreter?.close();
      receivePort.close();
      return;
    }

    if (message is SearchRequest) {
      try {
        String query = message.query;
        final db = await dbHelper.database;

        String extraWhere = '';
        
        // --- Temporal NLP Extraction ---
        final lowerQuery = query.toLowerCase();
        final now = DateTime.now();
        int? startTime;
        int? endTime;
        
        if (lowerQuery.contains('yesterday')) {
          query = lowerQuery.replaceAll('yesterday', '').trim();
          final yesterday = now.subtract(const Duration(days: 1));
          startTime = DateTime(yesterday.year, yesterday.month, yesterday.day).millisecondsSinceEpoch;
          endTime = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch - 1;
        } else if (lowerQuery.contains('last week')) {
          query = lowerQuery.replaceAll('last week', '').trim();
          final lastWeek = now.subtract(const Duration(days: 7));
          startTime = DateTime(lastWeek.year, lastWeek.month, lastWeek.day).millisecondsSinceEpoch;
        } else if (lowerQuery.contains('last month')) {
          query = lowerQuery.replaceAll('last month', '').trim();
          final lastMonth = now.subtract(const Duration(days: 30));
          startTime = DateTime(lastMonth.year, lastMonth.month, lastMonth.day).millisecondsSinceEpoch;
        }
        
        if (startTime != null) extraWhere += ' AND m.date >= $startTime';
        if (endTime != null) extraWhere += ' AND m.date <= $endTime';
        // -------------------------------

        if (message.filters.contains('Unread')) {
          extraWhere += ' AND m.read = 0';
        }
        if (message.filters.contains('Starred')) {
          extraWhere += ' AND m.isStarred = 1';
        }
        if (message.filters.contains('Has Link')) {
          extraWhere += " AND (m.body LIKE '%http%' OR m.body LIKE '%www.%')";
        }
        if (message.filters.contains('Has Date')) {
          // Extremely rudimentary heuristic for date (e.g. contains 202 or / or -)
          extraWhere += " AND (m.body LIKE '%/%/%' OR m.body LIKE '%-%-%' OR m.body LIKE '%202%')";
        }
        if (message.filters.contains('Has Number')) {
          extraWhere += " AND m.body GLOB '*[0-9][0-9][0-9]*'";
        }

        // 1. Exact Match via FTS4
        // Sanitize query for FTS4 (escape quotes and wrap)
        final sanitizedQuery = '${query.replaceAll('"', '""')}*';

        final ftsResults = await db.rawQuery(
          '''
          SELECT f.docid 
          FROM messages_fts f
          INNER JOIN messages m ON f.docid = m.id
          WHERE f.messages_fts MATCH ? $extraWhere
          ORDER BY m.date DESC
          LIMIT 100
        ''',
          [sanitizedQuery],
        );

        final ftsRanks = <int, double>{};
        for (int i = 0; i < ftsResults.length; i++) {
          ftsRanks[ftsResults[i]['docid'] as int] = (i + 1)
              .toDouble(); // Rank by newest exact match
        }

        // 2. Vector Search (if interpreter is valid)
        final vectorRanks = <int, double>{};
        if (interpreter != null && tokenizer != null) {
          // Tokenize query
          final bertInput = tokenizer.prepareNerInput(query, 128);

          final searchInputIds = List.generate(
            1,
            (i) => List<int>.filled(128, 0),
          );
          final searchAttentionMask = List.generate(
            1,
            (i) => List<int>.filled(128, 0),
          );
          final searchOutput = List.generate(
            1,
            (i) => List<double>.filled(384, 0.0),
          );

          for (int i = 0; i < 128; i++) {
            searchInputIds[0][i] = bertInput.inputIds[i];
            searchAttentionMask[0][i] = bertInput.inputMask[i];
          }

          // Dynamically find correct tensor indices
          final inputTensors = interpreter.getInputTensors();
          final inputs = List<Object>.filled(inputTensors.length, 0);

          for (int i = 0; i < inputTensors.length; i++) {
            final name = inputTensors[i].name.toLowerCase();
            if (name.contains('input_ids') ||
                name == 'serving_default_inputs_1:0') {
              inputs[i] = searchInputIds;
            } else if (name.contains('mask') ||
                name.contains('attention') ||
                name == 'serving_default_inputs:0') {
              inputs[i] = searchAttentionMask;
            } else if (name.contains('type')) {
              inputs[i] = List.generate(1, (_) => List<int>.filled(128, 0));
            } else {
              // Fallback for an unknown 3rd tensor (usually token_type_ids)
              if (i == 2) {
                inputs[i] = List.generate(1, (_) => List<int>.filled(128, 0));
              }
            }
          }

          interpreter.runForMultipleInputs(inputs, {0: searchOutput});
          final List<double> queryEmbedding = searchOutput[0];

          // Fetch all embeddings that match filters
          final allDocs = await db.rawQuery(
            'SELECT m.id, m.embedding FROM messages m WHERE m.embedding IS NOT NULL $extraWhere',
          );

          final similarities = <_DocScore>[];
          for (final doc in allDocs) {
            final id = doc['id'] as int;
            final blob = doc['embedding'] as Uint8List;
            final byteData = ByteData.view(blob.buffer);
            double dotProduct = 0.0;
            double normA = 0.0;
            double normB = 0.0;
            for (int i = 0; i < 384; i++) {
              final a = queryEmbedding[i];
              final b = byteData.getFloat32(i * 4, Endian.host);
              dotProduct += a * b;
              normA += a * a;
              normB += b * b;
            }
            final similarity = (normA == 0 || normB == 0)
                ? 0.0
                : (dotProduct / (sqrt(normA) * sqrt(normB)));
                
            // Threshold cutoff: discard extremely low confidence semantic matches
            if (similarity > 0.30) {
              similarities.add(_DocScore(id, similarity));
            }
          }

          // Sort by similarity descending
          similarities.sort((a, b) => b.score.compareTo(a.score));

          for (int i = 0; i < similarities.length; i++) {
            vectorRanks[similarities[i].id] = (i + 1).toDouble();
          }
        }

        // 3. Reciprocal Rank Fusion
        const k = 60.0;
        final allIds = <int>{...ftsRanks.keys, ...vectorRanks.keys};
        final rrfScores = <_DocScore>[];

        for (final id in allIds) {
          double score = 0.0;
          if (ftsRanks.containsKey(id)) {
            score +=
                (1.0 / (k + ftsRanks[id]!)) *
                1.5; // 1.5x weight for exact keyword matches
          }
          if (vectorRanks.containsKey(id)) {
            score += 1.0 / (k + vectorRanks[id]!);
          }
          rrfScores.add(_DocScore(id, score));
        }

        rrfScores.sort((a, b) => b.score.compareTo(a.score));

        // Get top 50
        final topIds = rrfScores.take(50).map((e) => e.id).toList();

        if (topIds.isEmpty) {
          message.replyTo.send([]);
          return;
        }

        // Fetch actual messages
        final placeholders = List.filled(topIds.length, '?').join(',');
        final finalMessages = await db.rawQuery(
          'SELECT * FROM messages WHERE id IN ($placeholders)',
          topIds,
        );

        // Keep sorting order
        final messageMap = {for (var m in finalMessages) m['id'] as int: m};
        final sortedFinalMessages = topIds
            .map((id) => messageMap[id])
            .whereType<Map<String, dynamic>>()
            .toList();

        message.replyTo.send(sortedFinalMessages);
      } catch (e) {
        print('Search error: $e');
        message.replyTo.send([]);
      }
      return;
    }

    if (message == 'start_batch' && !isProcessing) {
      isProcessing = true;
      try {
        final db = await dbHelper.database;

        // Fetch 50 messages without embeddings, joining threads for context
        final unindexedMessages = await db.rawQuery('''
          SELECT m.id, m.body, m.address, m.type, t.contactName 
          FROM messages m 
          LEFT JOIN threads t ON m.threadId = t.id 
          WHERE m.embedding IS NULL 
          LIMIT 50
        ''');

        if (unindexedMessages.isEmpty) {
          isProcessing = false;
          initData.sendPort.send('all_done');
          return;
        }

        final batch = db.batch();

        for (final row in unindexedMessages) {
          final id = row['id'] as int;
          final body = row['body'] as String;
          final address = row['address'] as String? ?? 'Unknown';
          final contactName = row['contactName'] as String?;
          final msgType = row['type'] as int? ?? 1; // 1 = Inbox/Received, 2 = Sent

          final sender = contactName != null && contactName.isNotEmpty
              ? contactName
              : address;

          // Differentiate context based on whether the message was sent or received
          final text = (msgType == 2) 
              ? "Sent to: $sender. Message: $body"
              : "Received from: $sender. Message: $body";

          // Tokenize using BertTokenizer
          final bertInput = tokenizer!.prepareNerInput(text, 128);

          for (int i = 0; i < 128; i++) {
            inputIdsArray[0][i] = bertInput.inputIds[i];
            attentionMaskArray[0][i] = bertInput.inputMask[i];
          }

          // Dynamically find correct tensor indices
          final inputTensors = interpreter!.getInputTensors();
          final inputs = List<Object>.filled(inputTensors.length, 0);

          for (int i = 0; i < inputTensors.length; i++) {
            final name = inputTensors[i].name.toLowerCase();
            if (name.contains('input_ids') ||
                name == 'serving_default_inputs_1:0') {
              inputs[i] = inputIdsArray;
            } else if (name.contains('mask') ||
                name.contains('attention') ||
                name == 'serving_default_inputs:0') {
              inputs[i] = attentionMaskArray;
            } else if (name.contains('type')) {
              inputs[i] = List.generate(1, (_) => List<int>.filled(128, 0));
            } else {
              // Fallback for an unknown 3rd tensor (usually token_type_ids)
              if (i == 2) {
                inputs[i] = List.generate(1, (_) => List<int>.filled(128, 0));
              }
            }
          }

          interpreter.runForMultipleInputs(inputs, {0: outputArray});

          // Get embedding and convert to bytes
          final embedding = outputArray[0];
          final byteData = ByteData(384 * 4); // 384 floats * 4 bytes
          for (int i = 0; i < 384; i++) {
            byteData.setFloat32(i * 4, embedding[i], Endian.host);
          }
          final blob = byteData.buffer.asUint8List();

          batch.update(
            'messages',
            {'embedding': blob},
            where: 'id = ?',
            whereArgs: [id],
          );
        }

        await batch.commit(noResult: true);
        isProcessing = false;
        initData.sendPort.send('batch_done');
      } catch (e) {
        initData.sendPort.send('error: Batch processing failed: $e');
        isProcessing = false;
        initData.sendPort.send('all_done');
      }
    }
  });
}

class _DocScore {
  final int id;
  final double score;
  _DocScore(this.id, this.score);
}
