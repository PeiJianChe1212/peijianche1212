class ApiSettings {
  const ApiSettings({
    this.provider = 'DeepSeek',
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
  final String provider;
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
    String? provider,
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
