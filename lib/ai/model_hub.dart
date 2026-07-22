import 'package:http/http.dart' as http;

import '../models/ai_capability.dart';
import '../services/api_settings_storage_service.dart';
import 'chat_model_provider.dart';
import 'image_model_provider.dart';
import 'speech_to_text_provider.dart';
import 'text_to_speech_provider.dart';
import 'providers/openai_compatible_chat_provider.dart';

class ModelHub {
  ModelHub({
    ApiSettingsStorageService? storage,
    http.Client? client,
  }) : _storage = storage ?? ApiSettingsStorageService(),
       _client = client;

  final ApiSettingsStorageService _storage;
  final http.Client? _client;

  Future<ChatModelProvider> chatProvider() async {
    final settings = await _storage.loadSettings();
    return OpenAiCompatibleChatProvider(settings: settings, client: _client);
  }

  Future<ImageModelProvider?> imageProvider() async => null;

  Future<TextToSpeechProvider?> textToSpeechProvider() async => null;

  Future<SpeechToTextProvider?> speechToTextProvider() async => null;

  Future<bool> isConfigured(AiCapability capability) async {
    switch (capability) {
      case AiCapability.chat:
        return (await _storage.loadSettings()).isConfigured;
      case AiCapability.imageGeneration:
      case AiCapability.textToSpeech:
      case AiCapability.speechToText:
        return false;
    }
  }

  bool isFrameworkReady(AiCapability capability) => true;
}
