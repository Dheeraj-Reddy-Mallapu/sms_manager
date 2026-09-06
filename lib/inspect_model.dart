import 'dart:io';

import 'package:flutter_litert/flutter_litert.dart';

void main() {
  final modelPath = 'e:/flutter/sms_manager/assets/nihal-minilm.tflite';
  final interpreter = Interpreter.fromFile(File(modelPath));

  print('--- INPUT TENSORS ---');
  final inputs = interpreter.getInputTensors();
  for (var i = 0; i < inputs.length; i++) {
    final tensor = inputs[i];
    print(
      'Index \$i: \${tensor.name} (type: \${tensor.type}, shape: \${tensor.shape})',
    );
  }

  print('--- OUTPUT TENSORS ---');
  final outputs = interpreter.getOutputTensors();
  for (var i = 0; i < outputs.length; i++) {
    final tensor = outputs[i];
    print(
      'Index \$i: \${tensor.name} (type: \${tensor.type}, shape: \${tensor.shape})',
    );
  }
}
