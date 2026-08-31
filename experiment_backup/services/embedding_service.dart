import 'dart:math';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:bert_tokenizer/bert_tokenizer.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

class EmbeddingService {
  late Interpreter _interpreter;
  late BertTokenizer _tokenizer;
  bool _isInitialized = false;

  int _inputTypeCount = 1;

  static String? _modelFilePath;
  static String? _tokenizerFilePath;

  static Future<void> extractAssets() async {
    if (_modelFilePath != null && _tokenizerFilePath != null) return;

    final tempDir = await getTemporaryDirectory();

    // Extract MiniLM Model (22MB INT8 version)
    final modelFile = File('${tempDir.path}/minilm_nihal.tflite');
    if (!await modelFile.exists()) {
      final modelData = await rootBundle.load('assets/nihal-minilm.tflite');
      await modelFile.writeAsBytes(modelData.buffer.asUint8List(), flush: true);
    }
    _modelFilePath = modelFile.path;

    // Extract WordPiece Vocab (226KB)
    final tokenizerFile = File('${tempDir.path}/vocab.txt');
    if (!await tokenizerFile.exists()) {
      final tokenizerData = await rootBundle.load('assets/vocab.txt');
      await tokenizerFile.writeAsBytes(
        tokenizerData.buffer.asUint8List(),
        flush: true,
      );
    }
    _tokenizerFilePath = tokenizerFile.path;
  }

  Future<void> initialize(String modelPath, String tokenizerPath) async {
    if (_isInitialized) return;

    final options = InterpreterOptions();
    options.addDelegate(
      XNNPackDelegate(options: XNNPackDelegateOptions(numThreads: 4)),
    );

    _interpreter = Interpreter.fromFile(File(modelPath), options: options);

    _inputTypeCount = _interpreter.getInputTensors().length;

    // Resize input tensors from [1, 1] to [1, 256] for the dynamic model
    for (int i = 0; i < _inputTypeCount; i++) {
      _interpreter.resizeInputTensor(i, [1, 256]);
    }
    _interpreter.allocateTensors();

    // Read the vocab file content for the BERT tokenizer
    final vocabContent = File(tokenizerPath).readAsStringSync();
    _tokenizer = BertTokenizer.fromStringContent(vocabContent);

    _isInitialized = true;
  }

  Future<List<double>> getEmbedding(
    String text, {
    bool isQuery = false,
    SmsMessage? metadata,
  }) async {
    if (!_isInitialized) throw Exception("EmbeddingService not initialized");

    // MiniLM uses a different prefix format than Gemma if any, but standard sentence-transformers
    // usually don't strictly require task prefixes like Gemma does, though 'query: ' and 'passage: '
    // are sometimes used for other models like E5. For all-MiniLM-L6-v2, it doesn't use prefixes!
    // We just feed the raw text.
    final encoding = _tokenizer.prepareNerInput(text, 256);

    var inputIds = [encoding.inputIds];
    var inputMask = [encoding.inputMask];
    var segmentIds = [encoding.segmentIds];

    // MiniLM output is 384 dimensions, not 768!
    var outputTensor = [List.filled(384, 0.0)];

    // Depending on how the TFLite model was exported, it takes either 1, 2, or 3 inputs.
    if (_inputTypeCount == 3) {
      // Typically: input_ids, attention_mask, token_type_ids
      _interpreter.runForMultipleInputs(
        [inputIds, inputMask, segmentIds],
        {0: outputTensor},
      );
    } else if (_inputTypeCount == 2) {
      // Nihal model uses 2 inputs: input_ids, attention_mask
      _interpreter.runForMultipleInputs(
        [inputIds, inputMask],
        {0: outputTensor},
      );
    } else {
      _interpreter.run(inputIds, outputTensor);
    }

    return outputTensor[0];
  }

  double cosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.length != v2.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < v1.length; i++) {
      dotProduct += v1[i] * v2[i];
      normA += pow(v1[i], 2);
      normB += pow(v2[i], 2);
    }

    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
}
