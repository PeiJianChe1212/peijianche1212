import 'package:http/http.dart' as http;

import '../ai/image_generation/image_generation_adapter.dart';
import '../ai/image_generation/openai_compatible_image_adapter.dart';
import '../ai/image_generation/volcengine_image_adapter.dart';
import '../models/api_settings.dart';
import '../models/image_generation_settings.dart';
import '../models/vision_settings.dart';

typedef ImageGenerationAdapterFactory =
    ImageGenerationAdapter Function({
      required ImageGenerationProvider provider,
      required String apiKey,
      required String endpointUrl,
      required String model,
    });

class ImageGenerationRouter {
  factory ImageGenerationRouter({
    http.Client? client,
    ImageGenerationAdapterFactory? adapterFactory,
  }) => ImageGenerationRouter._(client, adapterFactory);

  ImageGenerationRouter._(this._client, this._adapterFactory);

  final http.Client? _client;
  final ImageGenerationAdapterFactory? _adapterFactory;

  ImageGenerationAdapter resolve({
    required ImageGenerationSettings settings,
    required ApiSettings chatSettings,
    required VisionSettings visionSettings,
  }) {
    final apiKey = settings.effectiveApiKey(
      chatSettings: chatSettings,
      visionSettings: visionSettings,
    );
    final endpointUrl = ImageGenerationEndpointResolver.generationsUrl(
      settings.effectiveBaseUrl,
    );
    final factory = _adapterFactory;
    if (factory != null) {
      return factory(
        provider: settings.provider,
        apiKey: apiKey,
        endpointUrl: endpointUrl,
        model: settings.model,
      );
    }
    if (settings.provider == ImageGenerationProvider.volcengine) {
      return VolcengineImageAdapter(
        apiKey: apiKey,
        endpointUrl: endpointUrl,
        model: settings.model,
        client: _client,
      );
    }
    return OpenAiCompatibleImageAdapter(
      adapterName: settings.provider.label,
      apiKey: apiKey,
      endpointUrl: endpointUrl,
      model: settings.model,
      client: _client,
    );
  }
}
