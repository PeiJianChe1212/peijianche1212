class ApiSettings {
  const ApiSettings({
    this.provider = 'DeepSeek',
    this.apiKey = '',
    this.baseUrl = 'https://api.deepseek.com/v1/chat/completions',
    this.model = 'deepseek-chat',
  });

  final String provider;
  final String apiKey;
  final String baseUrl;
  final String model;

  bool get isConfigured =>
      apiKey.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  ApiSettings copyWith({
    String? provider,
    String? apiKey,
    String? baseUrl,
    String? model,
  }) {
    return ApiSettings(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
    );
  }
}
