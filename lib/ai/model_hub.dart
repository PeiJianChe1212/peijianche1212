import 'package:http/http.dart' as http;

import '../models/ai_capability.dart';
import '../models/api_settings.dart';
import '../services/api_settings_storage_service.dart';
import 'chat_model_provider.dart';
import 'image_model_provider.dart';
import 'providers/openai_compatible_chat_provider.dart';
import 'providers/volcengine_image_provider.dart';
import 'providers/volcengine_multimodal_provider.dart';
import 'speech_to_text_provider.dart';
import 'text_to_speech_provider.dart';

class ModelHub {
  ModelHub({ApiSettingsStorageService? storage, this.client})
    : _storage = storage ?? ApiSettingsStorageService();

  final ApiSettingsStorageService _storage;
  final http.Client? client;

  Future<ChatModelProvider> chatProvider({ApiSettings? settings}) async {
    final resolvedSettings = settings ?? await _storage.loadSettings();
    return OpenAiCompatibleChatProvider(
      settings: resolvedSettings,
      client: client,
    );
  }

  Future<VolcengineMultimodalProvider?> multimodalProvider() async {
    final settings = await _storage.loadSettings();
    if (!settings.isMultimodalConfigured) return null;
    return VolcengineMultimodalProvider(settings: settings, client: client);
  }

  @Deprecated('正式生图入口请使用 ImageGenerationService，由 Router 选择 Provider。')
  Future<ImageModelProvider?> imageProvider() async {
    final settings = await _storage.loadSettings();
    if (!settings.isImageConfigured) return null;
    return VolcengineImageProvider(settings: settings, client: client);
  }

  Future<TextToSpeechProvider?> textToSpeechProvider() async => null;

  Future<SpeechToTextProvider?> speechToTextProvider() async => null;

  Future<bool> isConfigured(AiCapability capability) async {
    final settings = await _storage.loadSettings();
    switch (capability) {
      case AiCapability.chat:
        return settings.isConfigured;
      case AiCapability.imageGeneration:
        return settings.isImageConfigured;
      case AiCapability.textToSpeech:
      case AiCapability.speechToText:
        return false;
    }
  }

  Future<bool> isMultimodalConfigured() async {
    return (await _storage.loadSettings()).isMultimodalConfigured;
  }

  bool isFrameworkReady(AiCapability capability) => true;
}
