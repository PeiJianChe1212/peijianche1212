import 'api_settings.dart';

enum VisionUsageMode { useChatModel, separateVisionModel }

enum VisionProvider { openai, volcengine, custom }

enum VisionCapabilityStatus { untested, supported, unsupported }

extension VisionProviderDetails on VisionProvider {
  String get label => switch (this) {
    VisionProvider.openai => 'OpenAI',
    VisionProvider.volcengine => '豆包 / 火山方舟',
    VisionProvider.custom => '自定义',
  };

  String get officialBaseUrl => switch (this) {
    VisionProvider.openai => AIProvider.openai.officialBaseUrl,
    VisionProvider.volcengine => AIProvider.volcengine.officialBaseUrl,
    VisionProvider.custom => '',
  };
}

class VisionSettings {
  const VisionSettings({
    this.usageMode = VisionUsageMode.useChatModel,
    this.provider = VisionProvider.openai,
    this.apiKey = '',
    this.reuseChatApiKey = false,
    this.baseUrl = '',
    this.model = '',
    this.capabilityStatus = VisionCapabilityStatus.untested,
  });

  final VisionUsageMode usageMode;
  final VisionProvider provider;
  final String apiKey;
  final bool reuseChatApiKey;
  final String baseUrl;
  final String model;
  final VisionCapabilityStatus capabilityStatus;

  String effectiveApiKey(ApiSettings chatSettings) {
    return reuseChatApiKey ? chatSettings.apiKey.trim() : apiKey.trim();
  }

  String effectiveBaseUrl(ApiSettings chatSettings) {
    if (usageMode == VisionUsageMode.useChatModel) {
      return chatSettings.baseUrl.trim();
    }
    final value = baseUrl.trim();
    return value.isNotEmpty ? value : provider.officialBaseUrl;
  }

  String effectiveModel(ApiSettings chatSettings) =>
      usageMode == VisionUsageMode.useChatModel
      ? chatSettings.model.trim()
      : model.trim();

  VisionSettings copyWith({
    VisionUsageMode? usageMode,
    VisionProvider? provider,
    String? apiKey,
    bool? reuseChatApiKey,
    String? baseUrl,
    String? model,
    VisionCapabilityStatus? capabilityStatus,
    bool clearCapabilityStatus = false,
  }) {
    return VisionSettings(
      usageMode: usageMode ?? this.usageMode,
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      reuseChatApiKey: reuseChatApiKey ?? this.reuseChatApiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      capabilityStatus: clearCapabilityStatus
          ? VisionCapabilityStatus.untested
          : capabilityStatus ?? this.capabilityStatus,
    );
  }
}

class VisionSettingsCodec {
  const VisionSettingsCodec._();

  static VisionSettings decode(
    Map<String, String> values, {
    required ApiSettings legacySettings,
  }) {
    if (!values.containsKey('vision_usage_mode')) {
      if (legacySettings.multimodalModel.trim().isNotEmpty) {
        return VisionSettings(
          usageMode: VisionUsageMode.separateVisionModel,
          provider: VisionProvider.volcengine,
          apiKey: legacySettings.multimodalApiKey,
          reuseChatApiKey: legacySettings.multimodalApiKey.trim().isEmpty,
          baseUrl: legacySettings.multimodalBaseUrl,
          model: legacySettings.multimodalModel,
        );
      }
      return const VisionSettings();
    }
    return VisionSettings(
      usageMode: _enumByName(
        VisionUsageMode.values,
        values['vision_usage_mode'],
        VisionUsageMode.useChatModel,
      ),
      provider: _enumByName(
        VisionProvider.values,
        values['vision_provider'],
        VisionProvider.openai,
      ),
      apiKey: values['vision_api_key'] ?? '',
      reuseChatApiKey: values['vision_reuse_chat_key'] == 'true',
      baseUrl: values['vision_base_url'] ?? '',
      model: values['vision_model'] ?? '',
      capabilityStatus: _enumByName(
        VisionCapabilityStatus.values,
        values['vision_capability_status'],
        VisionCapabilityStatus.untested,
      ),
    );
  }

  static Map<String, String> encode(VisionSettings settings) => {
    'vision_usage_mode': settings.usageMode.name,
    'vision_provider': settings.provider.name,
    'vision_api_key': settings.apiKey.trim(),
    'vision_reuse_chat_key': settings.reuseChatApiKey.toString(),
    'vision_base_url': settings.baseUrl.trim(),
    'vision_model': settings.model.trim(),
    'vision_capability_status': settings.capabilityStatus.name,
  };

  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) => values.where((value) => value.name == name).firstOrNull ?? fallback;
}
