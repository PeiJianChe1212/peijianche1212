import 'package:http/http.dart' as http;

import '../ai/vision/openai_compatible_vision_adapter.dart';
import '../ai/vision/volcengine_vision_adapter.dart';
import '../ai/vision/vision_adapter.dart';
import '../models/api_settings.dart';
import '../models/vision_settings.dart';

typedef VisionAdapterFactory =
    VisionAdapter Function({
      required String adapterName,
      required String apiKey,
      required String endpointUrl,
      required String model,
    });

class VisionRouter {
  factory VisionRouter({
    http.Client? client,
    VisionAdapterFactory? adapterFactory,
  }) => VisionRouter._(client, adapterFactory);

  VisionRouter._(this._client, this._adapterFactory);

  final http.Client? _client;
  final VisionAdapterFactory? _adapterFactory;

  VisionAdapter resolve({
    required VisionSettings visionSettings,
    required ApiSettings chatSettings,
  }) {
    if (visionSettings.usageMode == VisionUsageMode.useChatModel) {
      return _create(
        adapterName: '当前聊天模型 · ${chatSettings.provider.label}',
        apiKey: chatSettings.apiKey,
        endpointUrl: chatSettings.chatCompletionsUrl,
        model: chatSettings.model,
      );
    }
    final baseUrl = visionSettings.effectiveBaseUrl(chatSettings);
    if (visionSettings.provider == VisionProvider.volcengine) {
      return VolcengineVisionAdapter(
        apiKey: visionSettings.effectiveApiKey(chatSettings),
        endpointUrl: ApiEndpointResolver.chatCompletionsUrl(baseUrl),
        endpointId: visionSettings.model,
        client: _client,
      );
    }
    return _create(
      adapterName: visionSettings.provider.label,
      apiKey: visionSettings.effectiveApiKey(chatSettings),
      endpointUrl: ApiEndpointResolver.chatCompletionsUrl(baseUrl),
      model: visionSettings.model,
    );
  }

  VisionAdapter _create({
    required String adapterName,
    required String apiKey,
    required String endpointUrl,
    required String model,
  }) {
    final factory = _adapterFactory;
    if (factory != null) {
      return factory(
        adapterName: adapterName,
        apiKey: apiKey,
        endpointUrl: endpointUrl,
        model: model,
      );
    }
    return OpenAiCompatibleVisionAdapter(
      adapterName: adapterName,
      apiKey: apiKey,
      endpointUrl: endpointUrl,
      model: model,
      client: _client,
    );
  }
}
