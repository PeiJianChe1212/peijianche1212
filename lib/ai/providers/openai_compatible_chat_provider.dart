import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/ai_capability.dart';
import '../../models/api_settings.dart';
import '../chat_model_provider.dart';

class ChatEmptyResponseException implements Exception {
  const ChatEmptyResponseException({
    required this.finishReason,
    required this.hasReasoningContent,
  });

  final String finishReason;
  final bool hasReasoningContent;

  @override
  String toString() => '聊天模型没有返回可用正文。';
}

class OpenAiCompatibleChatProvider extends ChatModelProvider {
  OpenAiCompatibleChatProvider({required this.settings, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final ApiSettings settings;
  final http.Client _client;
  final bool _ownsClient;

  @override
  String get providerName => settings.provider.label;

  @override
  Set<AiCapability> get capabilities => const {AiCapability.chat};

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required int maxTokens,
    double? topP,
    bool acceptStructuredReasoningFallback = false,
  }) async {
    if (!settings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存聊天模型配置。');
    }

    final body = <String, dynamic>{
      'model': settings.model,
      'messages': messages,
      'stream': false,
      if (settings.provider == AIProvider.openai)
        'max_completion_tokens': maxTokens
      else
        'max_tokens': maxTokens,
      if (settings.provider != AIProvider.openai) ...{
        'temperature': temperature,
        'top_p': ?topP,
      },
    };

    final response = await _client
        .post(
          Uri.parse(settings.chatCompletionsUrl),
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
    if (message is! Map) {
      throw const FormatException('API 没有返回回复内容');
    }

    var content = _readMessageContent(message['content']);
    final reasoning = message['reasoning_content']?.toString().trim() ?? '';
    if (content.isEmpty && acceptStructuredReasoningFallback) {
      content = _readStructuredReasoningFallback(reasoning);
    }
    if (content.isEmpty) {
      throw ChatEmptyResponseException(
        finishReason: firstChoice['finish_reason']?.toString().trim() ?? '',
        hasReasoningContent: reasoning.isNotEmpty,
      );
    }

    return content;
  }

  String _readMessageContent(dynamic raw) {
    if (raw is String) return raw.trim();
    if (raw is List) {
      return raw
          .map((part) {
            if (part is String) return part;
            if (part is Map) {
              final text = part['text'];
              if (text is String) return text;
              final nested = part['content'];
              if (nested is String) return nested;
            }
            return '';
          })
          .where((part) => part.trim().isNotEmpty)
          .join('\n')
          .trim();
    }
    return '';
  }

  String _readStructuredReasoningFallback(String reasoning) {
    var value = reasoning.trim();
    value = value.replaceFirst(
      RegExp(r'^```(?:json)?\s*', caseSensitive: false),
      '',
    );
    value = value.replaceFirst(RegExp(r'\s*```$'), '');
    final objectStart = value.indexOf('{');
    final arrayStart = value.indexOf('[');
    final start =
        objectStart >= 0 && (arrayStart < 0 || objectStart < arrayStart)
        ? objectStart
        : arrayStart;
    if (start < 0) return '';
    final candidate = value.substring(start).trim();
    final completeObject = candidate.startsWith('{') && candidate.endsWith('}');
    final completeArray = candidate.startsWith('[') && candidate.endsWith(']');
    return completeObject || completeArray ? candidate : '';
  }

  String _extractError(String responseText) {
    try {
      final data = jsonDecode(responseText);
      if (data is Map && data['error'] is Map) {
        final message = data['error']['message'];
        if (message != null) {
          final raw = message.toString();
          return settings.apiKey.isEmpty
              ? raw
              : raw.replaceAll(settings.apiKey, '••••');
        }
      }
    } catch (_) {
      // 返回内容不是 JSON 时，直接显示原始文本。
    }

    return '服务返回了无法识别的错误信息';
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
