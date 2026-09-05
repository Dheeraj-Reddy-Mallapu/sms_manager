import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:flutter/foundation.dart';

import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Inspect TFLite model', () async {
    final file = File('assets/nihal-minilm.tflite');
    final interpreter = Interpreter.fromFile(file);

    debugPrint('Inputs:');
    for (var tensor in interpreter.getInputTensors()) {
      debugPrint('${tensor.name}: shape ${tensor.shape}, type ${tensor.type}');
    }

    debugPrint('Outputs:');
    for (var tensor in interpreter.getOutputTensors()) {
      debugPrint('${tensor.name}: shape ${tensor.shape}, type ${tensor.type}');
    }
  });
}
