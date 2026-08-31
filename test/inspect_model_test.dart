import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_litert/flutter_litert.dart';

import 'dart:io';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Inspect TFLite model', () async {
    final file = File('assets/nihal-minilm.tflite');
    final interpreter = Interpreter.fromFile(file);

    print('Inputs:');
    for (var tensor in interpreter.getInputTensors()) {
      print('${tensor.name}: shape ${tensor.shape}, type ${tensor.type}');
    }

    print('Outputs:');
    for (var tensor in interpreter.getOutputTensors()) {
      print('${tensor.name}: shape ${tensor.shape}, type ${tensor.type}');
    }
  });
}
