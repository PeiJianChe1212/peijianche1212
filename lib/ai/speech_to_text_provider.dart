import 'dart:typed_data';

import 'ai_model_provider.dart';

abstract class SpeechToTextProvider extends AiModelProvider {
  Future<String> transcribe({
    required Uint8List audioBytes,
    required String mimeType,
  });
}
