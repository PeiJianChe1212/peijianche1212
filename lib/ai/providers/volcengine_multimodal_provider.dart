import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/api_settings.dart';

class VolcengineMultimodalProvider {
  VolcengineMultimodalProvider({
    required this.settings,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final ApiSettings settings;
  final http.Client _client;
  final bool _ownsClient;

  Future<String> understandImage({
    required String imagePath,
    required String instruction,
    String? systemPrompt,
    int maxTokens = 900,
  }) async {
    if (!settings.isMultimodalConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中配置豆包识图模型。');
    }

    final file = File(imagePath);
    if (!await file.exists()) {
      throw ArgumentError('找不到需要识别的图片：$imagePath');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw const FormatException('图片文件为空。');

    final mimeType = _mimeTypeForPath(imagePath);
    final dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';

    final messages = <Map<String, dynamic>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt.trim()});
    }
    messages.add({
      'role': 'user',
      'content': [
        {
          'type': 'image_url',
          'image_url': {'url': dataUrl},
        },
        {'type': 'text', 'text': instruction.trim()},
      ],
    });

    return _complete(messages: messages, maxTokens: maxTokens);
  }

  Future<String> completeText({
    required String instruction,
    String? systemPrompt,
    int maxTokens = 500,
  }) async {
    if (!settings.isMultimodalConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中配置豆包识图模型。');
    }

    final messages = <Map<String, dynamic>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt.trim()});
    }
    messages.add({'role': 'user', 'content': instruction.trim()});
    return _complete(messages: messages, maxTokens: maxTokens);
  }

  Future<String> _complete({
    required List<Map<String, dynamic>> messages,
    required int maxTokens,
  }) async {
    final response = await _client
        .post(
          Uri.parse(settings.multimodalBaseUrl),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer ${settings.effectiveMultimodalApiKey}',
          },
          body: jsonEncode({
            'model': settings.multimodalModel,
            'messages': messages,
            'stream': false,
            'max_tokens': maxTokens,
            'temperature': 0.35,
          }),
        )
        .timeout(const Duration(seconds: 60));

    final responseText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        '识图 API ${response.statusCode}：${_extractError(responseText)}',
      );
    }

    final data = jsonDecode(responseText);
    if (data is! Map) throw const FormatException('识图接口返回格式错误。');
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('识图接口没有返回 choices。');
    }
    final first = choices.first;
    if (first is! Map || first['message'] is! Map) {
      throw const FormatException('识图接口返回内容格式错误。');
    }
    final content = (first['message'] as Map)['content']?.toString().trim() ?? '';
    if (content.isEmpty) throw const FormatException('识图接口返回了空内容。');
    return content;
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
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
