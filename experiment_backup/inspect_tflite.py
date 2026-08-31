import tensorflow as tf
try:
    interpreter = tf.lite.Interpreter(model_path='assets/all-MiniLM-L6-v2-int8.tflite')
    for input_detail in interpreter.get_input_details():
        print(f"Input: {input_detail['name']}, Shape: {input_detail['shape']}, Type: {input_detail['dtype']}")
    for output_detail in interpreter.get_output_details():
        print(f"Output: {output_detail['name']}, Shape: {output_detail['shape']}, Type: {output_detail['dtype']}")
except Exception as e:
    print(e)
