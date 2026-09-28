import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/ai_capability.dart';
import '../../models/api_settings.dart';
import '../image_model_provider.dart';
import '../../services/third_party_consent_service.dart';

class VolcengineImageProvider extends ImageModelProvider {
  VolcengineImageProvider({required this.settings, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final ApiSettings settings;
  final http.Client _client;
  final bool _ownsClient;

  @override
  String get providerName => '豆包图像创作';

  @override
  Set<AiCapability> get capabilities => const {
    AiCapability.imageGeneration,
  };

  @override
  Future<GeneratedImage> generate({
    required String prompt,
    String? negativePrompt,
    int width = 1024,
    int height = 1024,
  }) async {
    if (!settings.isImageConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中配置豆包图片模型。');
    }

    await ThirdPartyConsentService.instance.requireConsent(
      AIProvider.volcengine,
      settings.imageBaseUrl,
      ConsentPurpose.imageGeneration,
    );
    final cleanedPrompt = prompt.trim();
    if (cleanedPrompt.isEmpty) throw ArgumentError('生图描述不能为空。');

    final mergedPrompt = negativePrompt == null || negativePrompt.trim().isEmpty
        ? cleanedPrompt
        : '$cleanedPrompt\n避免出现：${negativePrompt.trim()}';

    final response = await _client
        .post(
          Uri.parse(settings.imageBaseUrl),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer ${settings.effectiveImageApiKey}',
          },
          body: jsonEncode({
            'model': settings.imageModel,
            'prompt': mergedPrompt,
            'size': '${width}x$height',
            'response_format': 'url',
            'watermark': false,
          }),
        )
        .timeout(const Duration(seconds: 120));

    final responseText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        '生图 API ${response.statusCode}：${_extractError(responseText)}',
      );
    }

    final data = jsonDecode(responseText);
    if (data is! Map || data['data'] is! List || (data['data'] as List).isEmpty) {
      throw const FormatException('生图接口没有返回图片。');
    }

    final first = (data['data'] as List).first;
    if (first is! Map) throw const FormatException('生图接口返回格式错误。');
    final url = first['url']?.toString().trim() ?? '';
    if (url.isEmpty) throw const FormatException('生图接口没有返回图片地址。');

    return GeneratedImage(
      url: url,
      revisedPrompt: first['revised_prompt']?.toString(),
    );
  }

  String _extractError(String responseText) {
    try {
      final data = jsonDecode(responseText);
      if (data is Map && data['error'] is Map) {
        return data['error']['message']?.toString() ?? responseText;
      }
    } catch (_) {}
    return responseText;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
