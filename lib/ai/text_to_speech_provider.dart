import 'dart:typed_data';

import 'ai_model_provider.dart';

class GeneratedAudio {
  const GeneratedAudio({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
}

abstract class TextToSpeechProvider extends AiModelProvider {
  Future<GeneratedAudio> synthesize({
    required String text,
    String? voiceId,
  });
}
