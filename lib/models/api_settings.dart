enum AIProvider { deepseek, volcengine, openai, custom }

extension AIProviderDetails on AIProvider {
  String get label => switch (this) {
    AIProvider.deepseek => 'DeepSeek',
    AIProvider.volcengine => '豆包 / 火山方舟',
    AIProvider.openai => 'OpenAI',
    AIProvider.custom => '自定义',
  };

  static AIProvider fromStored(String? value) => AIProvider.values.firstWhere(
    (provider) => provider.name == value || provider.label == value,
    orElse: () => AIProvider.deepseek,
  );

  String get officialBaseUrl => switch (this) {
    AIProvider.deepseek => 'https://api.deepseek.com/v1',
    AIProvider.volcengine => 'https://ark.cn-beijing.volces.com/api/v3',
    AIProvider.openai => 'https://api.openai.com/v1',
    AIProvider.custom => '',
  };

  bool get usesOfficialBaseUrl => this != AIProvider.custom;
}

class ApiSettings {
  const ApiSettings({
    this.provider = AIProvider.deepseek,
    this.apiKey = '',
    this.baseUrl = 'https://api.deepseek.com/v1/chat/completions',
    this.model = 'deepseek-chat',
    this.multimodalApiKey = '',
    this.multimodalBaseUrl =
        'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
    this.multimodalModel = '',
    this.imageApiKey = '',
    this.imageBaseUrl =
        'https://ark.cn-beijing.volces.com/api/v3/images/generations',
    this.imageModel = '',
  });

  /// 日常文字聊天模型。保留旧字段名，避免已有聊天代码大面积改动。
  final AIProvider provider;
  final String apiKey;
  final String baseUrl;
  final String model;

  /// 豆包多模态模型：负责识图、理解画面和整理生图描述。
  final String multimodalApiKey;
  final String multimodalBaseUrl;
  final String multimodalModel;

  /// 豆包图片模型：只负责把提示词变成图片。
  final String imageApiKey;
  final String imageBaseUrl;
  final String imageModel;

  bool get isConfigured =>
      apiKey.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  String get chatCompletionsUrl {
    final configured = baseUrl.trim().isEmpty
        ? provider.officialBaseUrl
        : baseUrl.trim();
    return ApiEndpointResolver.chatCompletionsUrl(configured);
  }

  bool get isMultimodalConfigured =>
      effectiveMultimodalApiKey.isNotEmpty &&
      multimodalBaseUrl.trim().isNotEmpty &&
      multimodalModel.trim().isNotEmpty;

  bool get isImageConfigured =>
      effectiveImageApiKey.isNotEmpty &&
      imageBaseUrl.trim().isNotEmpty &&
      imageModel.trim().isNotEmpty;

  /// 火山方舟通常可共用同一把 API Key。专用 Key 留空时自动复用聊天 Key。
  String get effectiveMultimodalApiKey {
    final value = multimodalApiKey.trim();
    return value.isNotEmpty ? value : apiKey.trim();
  }

  String get effectiveImageApiKey {
    final value = imageApiKey.trim();
    return value.isNotEmpty ? value : apiKey.trim();
  }

  ApiSettings copyWith({
    AIProvider? provider,
    String? apiKey,
    String? baseUrl,
    String? model,
    String? multimodalApiKey,
    String? multimodalBaseUrl,
    String? multimodalModel,
    String? imageApiKey,
    String? imageBaseUrl,
    String? imageModel,
  }) {
    return ApiSettings(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      multimodalApiKey: multimodalApiKey ?? this.multimodalApiKey,
      multimodalBaseUrl: multimodalBaseUrl ?? this.multimodalBaseUrl,
      multimodalModel: multimodalModel ?? this.multimodalModel,
      imageApiKey: imageApiKey ?? this.imageApiKey,
      imageBaseUrl: imageBaseUrl ?? this.imageBaseUrl,
      imageModel: imageModel ?? this.imageModel,
    );
  }
}

class ApiEndpointResolver {
  const ApiEndpointResolver._();

  static String chatCompletionsUrl(String baseUrl) {
    final uri = _normalizedUri(baseUrl);
    final segments = _withoutKnownEndpoint(uri.pathSegments);
    return uri
        .replace(pathSegments: [...segments, 'chat', 'completions'])
        .toString();
  }

  static String modelsUrl(String baseUrl) {
    final uri = _normalizedUri(baseUrl);
    final segments = _withoutKnownEndpoint(uri.pathSegments);
    return uri.replace(pathSegments: [...segments, 'models']).toString();
  }

  static Uri _normalizedUri(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse(trimmed);
    if (!uri.hasScheme || !uri.hasAuthority) {
      throw const FormatException('Base URL 格式不正确');
    }
    return uri;
  }

  static List<String> _withoutKnownEndpoint(List<String> pathSegments) {
    final segments = pathSegments.where((part) => part.isNotEmpty).toList();
    if (segments.isNotEmpty && segments.last == 'models') {
      segments.removeLast();
    } else if (segments.isNotEmpty && segments.last == 'responses') {
      segments.removeLast();
    } else if (segments.length >= 2 &&
        segments[segments.length - 2] == 'chat' &&
        segments.last == 'completions') {
      segments.removeRange(segments.length - 2, segments.length);
    }
    return segments;
  }
}
