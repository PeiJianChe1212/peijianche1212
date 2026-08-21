import 'api_settings.dart';
import 'vision_settings.dart';

enum ImageGenerationProvider { volcengine, openai, custom }

enum ImageGenerationProtocol { openAiImagesCompatible }

enum ImageApiKeySource { independent, chat, vision }

enum ImageGenerationCapabilityStatus { untested, supported, unsupported }

extension ImageGenerationProviderDetails on ImageGenerationProvider {
  String get label => switch (this) {
    ImageGenerationProvider.volcengine => '豆包 / 火山方舟',
    ImageGenerationProvider.openai => 'OpenAI',
    ImageGenerationProvider.custom => '自定义',
  };

  String get officialBaseUrl => switch (this) {
    ImageGenerationProvider.volcengine => AIProvider.volcengine.officialBaseUrl,
    ImageGenerationProvider.openai => AIProvider.openai.officialBaseUrl,
    ImageGenerationProvider.custom => '',
  };

  bool get supportsModelDiscovery => this != ImageGenerationProvider.volcengine;
  bool get showsCustomBaseUrl => this == ImageGenerationProvider.custom;
  bool get requiresEndpointId => this == ImageGenerationProvider.volcengine;
}

class ImageGenerationSettings {
  const ImageGenerationSettings({
    this.provider = ImageGenerationProvider.volcengine,
    this.apiKey = '',
    this.apiKeySource = ImageApiKeySource.independent,
    this.baseUrl = '',
    this.model = '',
    this.protocol = ImageGenerationProtocol.openAiImagesCompatible,
    this.capabilityStatus = ImageGenerationCapabilityStatus.untested,
  });

  final ImageGenerationProvider provider;
  final String apiKey;
  final ImageApiKeySource apiKeySource;
  final String baseUrl;
  final String model;
  final ImageGenerationProtocol protocol;
  final ImageGenerationCapabilityStatus capabilityStatus;

  String effectiveApiKey({
    required ApiSettings chatSettings,
    required VisionSettings visionSettings,
  }) => switch (apiKeySource) {
    ImageApiKeySource.independent => apiKey.trim(),
    ImageApiKeySource.chat =>
      _matchesChatProvider(chatSettings) ? chatSettings.apiKey.trim() : '',
    ImageApiKeySource.vision =>
      _matchesVisionProvider(visionSettings, chatSettings)
          ? visionSettings.effectiveApiKey(chatSettings)
          : '',
  };

  bool _matchesChatProvider(ApiSettings chatSettings) => switch (provider) {
    ImageGenerationProvider.openai =>
      chatSettings.provider == AIProvider.openai,
    ImageGenerationProvider.volcengine =>
      chatSettings.provider == AIProvider.volcengine,
    ImageGenerationProvider.custom =>
      chatSettings.provider == AIProvider.custom,
  };

  bool _matchesVisionProvider(
    VisionSettings visionSettings,
    ApiSettings chatSettings,
  ) {
    if (visionSettings.usageMode == VisionUsageMode.useChatModel) {
      return _matchesChatProvider(chatSettings);
    }
    return switch (provider) {
      ImageGenerationProvider.openai =>
        visionSettings.provider == VisionProvider.openai,
      ImageGenerationProvider.volcengine =>
        visionSettings.provider == VisionProvider.volcengine,
      ImageGenerationProvider.custom =>
        visionSettings.provider == VisionProvider.custom,
    };
  }

  String get effectiveBaseUrl {
    final value = baseUrl.trim();
    return value.isNotEmpty ? value : provider.officialBaseUrl;
  }

  ImageGenerationSettings copyWith({
    ImageGenerationProvider? provider,
    String? apiKey,
    ImageApiKeySource? apiKeySource,
    String? baseUrl,
    String? model,
    ImageGenerationProtocol? protocol,
    ImageGenerationCapabilityStatus? capabilityStatus,
    bool clearCapabilityStatus = false,
  }) => ImageGenerationSettings(
    provider: provider ?? this.provider,
    apiKey: apiKey ?? this.apiKey,
    apiKeySource: apiKeySource ?? this.apiKeySource,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    protocol: protocol ?? this.protocol,
    capabilityStatus: clearCapabilityStatus
        ? ImageGenerationCapabilityStatus.untested
        : capabilityStatus ?? this.capabilityStatus,
  );
}

class ImageGenerationEndpointResolver {
  const ImageGenerationEndpointResolver._();

  static String generationsUrl(String baseUrl) {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse(trimmed);
    if (!uri.hasScheme || !uri.hasAuthority) {
      throw const FormatException('Base URL 格式不正确');
    }
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (segments.length >= 2 &&
        segments[segments.length - 2] == 'images' &&
        segments.last == 'generations') {
      return uri.replace(pathSegments: segments).toString();
    }
    if (segments.length >= 2 &&
        segments[segments.length - 2] == 'chat' &&
        segments.last == 'completions') {
      segments.removeRange(segments.length - 2, segments.length);
    } else if (segments.isNotEmpty &&
        (segments.last == 'responses' || segments.last == 'models')) {
      segments.removeLast();
    }
    return uri
        .replace(pathSegments: [...segments, 'images', 'generations'])
        .toString();
  }
}

class ImageGenerationSettingsCodec {
  const ImageGenerationSettingsCodec._();

  static ImageGenerationSettings decode(
    Map<String, String> values, {
    required ApiSettings legacySettings,
  }) {
    if (!values.containsKey('image_generation_provider')) {
      return ImageGenerationSettings(
        provider: ImageGenerationProvider.volcengine,
        apiKey: legacySettings.effectiveImageApiKey,
        baseUrl: legacySettings.imageBaseUrl,
        model: legacySettings.imageModel,
      );
    }
    return ImageGenerationSettings(
      provider: _byName(
        ImageGenerationProvider.values,
        values['image_generation_provider'],
        ImageGenerationProvider.volcengine,
      ),
      apiKey: values['image_generation_api_key'] ?? '',
      apiKeySource: _byName(
        ImageApiKeySource.values,
        values['image_generation_key_source'],
        ImageApiKeySource.independent,
      ),
      baseUrl: values['image_generation_base_url'] ?? '',
      model: values['image_generation_model'] ?? '',
      protocol: _byName(
        ImageGenerationProtocol.values,
        values['image_generation_protocol'],
        ImageGenerationProtocol.openAiImagesCompatible,
      ),
      capabilityStatus: _byName(
        ImageGenerationCapabilityStatus.values,
        values['image_generation_capability_status'],
        ImageGenerationCapabilityStatus.untested,
      ),
    );
  }

  static Map<String, String> encode(ImageGenerationSettings settings) => {
    'image_generation_provider': settings.provider.name,
    'image_generation_api_key': settings.apiKey.trim(),
    'image_generation_key_source': settings.apiKeySource.name,
    'image_generation_base_url': settings.baseUrl.trim(),
    'image_generation_model': settings.model.trim(),
    'image_generation_protocol': settings.protocol.name,
    'image_generation_capability_status': settings.capabilityStatus.name,
  };

  static T _byName<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.where((value) => value.name == name).firstOrNull ?? fallback;
}
