import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/ai_capability.dart';
import '../../models/api_settings.dart';
import '../chat_model_provider.dart';

class OpenAiCompatibleChatProvider extends ChatModelProvider {
  OpenAiCompatibleChatProvider({required this.settings, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final ApiSettings settings;
  final http.Client _client;
  final bool _ownsClient;

  @override
  String get providerName => settings.provider;

  @override
  Set<AiCapability> get capabilities => const {AiCapability.chat};

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required int maxTokens,
    double? topP,
  }) async {
    if (!settings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存聊天模型配置。');
    }

    final body = <String, dynamic>{
      'model': settings.model,
      'messages': messages,
      'stream': false,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'top_p': ?topP,
    };

    final response = await _client
        .post(
          Uri.parse(settings.baseUrl),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer ${settings.apiKey}',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 45));

    final responseText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'API ${response.statusCode}：${_extractError(responseText)}',
      );
    }

    final data = jsonDecode(responseText);
    if (data is! Map) throw const FormatException('API 返回格式错误');

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('API 没有返回 choices');
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      throw const FormatException('API 返回内容格式错误');
    }

    final message = firstChoice['message'];
    if (message is! Map || message['content'] == null) {
      throw const FormatException('API 没有返回回复内容');
    }

    final content = message['content'].toString().trim();
    if (content.isEmpty) {
      throw const FormatException('API 返回了空回复');
    }

    return content;
  }

  String _extractError(String responseText) {
    try {
      final data = jsonDecode(responseText);
      if (data is Map && data['error'] is Map) {
        final message = data['error']['message'];
        if (message != null) return message.toString();
      }
    } catch (_) {
      // 返回内容不是 JSON 时，直接显示原始文本。
    }

    return responseText;
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
