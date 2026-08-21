import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'image_generation_adapter.dart';

class OpenAiCompatibleImageAdapter implements ImageGenerationAdapter {
  OpenAiCompatibleImageAdapter({
    required this.adapterName,
    required this.apiKey,
    required this.endpointUrl,
    required this.model,
    this.requestUrlResponse = false,
    this.includeWatermarkFlag = false,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  final String adapterName;
  final String apiKey;
  final String endpointUrl;
  final String model;
  final bool requestUrlResponse;
  final bool includeWatermarkFlag;
  final http.Client _client;

  @override
  Future<GeneratedImagePayload> generate({
    required String prompt,
    int width = 1024,
    int height = 1024,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const ImageGenerationException(
        ImageGenerationErrorKind.invalidApiKey,
        '请先填写图片生成 API Key',
      );
    }
    if (model.trim().isEmpty) {
      throw const ImageGenerationException(
        ImageGenerationErrorKind.modelUnavailable,
        '请先选择图片生成模型',
      );
    }
    final cleanedPrompt = prompt.trim();
    if (cleanedPrompt.isEmpty) {
      throw const ImageGenerationException(
        ImageGenerationErrorKind.requestFailed,
        '图片描述不能为空',
      );
    }
    final size = _safeSize(width, height);
    try {
      final response = await _client
          .post(
            Uri.parse(endpointUrl),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer ${apiKey.trim()}',
            },
            body: jsonEncode({
              'model': model.trim(),
              'prompt': cleanedPrompt,
              'size': size,
              if (requestUrlResponse) 'response_format': 'url',
              if (includeWatermarkFlag) 'watermark': false,
            }),
          )
          .timeout(const Duration(seconds: 120));
      final body = utf8.decode(response.bodyBytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _httpError(response.statusCode, body);
      }
      return parseResponse(body);
    } on ImageGenerationException {
      rethrow;
    } on TimeoutException {
      throw const ImageGenerationException(
        ImageGenerationErrorKind.timeout,
        '图片生成请求超时',
      );
    } on SocketException {
      throw const ImageGenerationException(
        ImageGenerationErrorKind.networkUnavailable,
        '网络不可用，无法连接图片生成服务',
      );
    } on http.ClientException {
      throw const ImageGenerationException(
        ImageGenerationErrorKind.networkUnavailable,
        '无法连接图片生成服务',
      );
    } on FormatException {
      throw const ImageGenerationException(
        ImageGenerationErrorKind.incompatibleProtocol,
        '图片生成接口返回格式不兼容',
      );
    }
  }

  static GeneratedImagePayload parseResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['data'] is! List) {
      throw const ImageGenerationException(
        ImageGenerationErrorKind.incompatibleProtocol,
        '接口不支持 OpenAI Images Compatible 协议',
      );
    }
    final data = decoded['data'] as List;
    if (data.isEmpty || data.first is! Map) {
      throw const ImageGenerationException(
        ImageGenerationErrorKind.invalidResult,
        '图片生成接口没有返回图片',
      );
    }
    final first = data.first as Map;
    final url = first['url']?.toString().trim();
    Uint8List? bytes;
    final encoded = first['b64_json']?.toString().trim() ?? '';
    if (encoded.isNotEmpty) {
      try {
        bytes = base64Decode(encoded);
      } on FormatException {
        throw const ImageGenerationException(
          ImageGenerationErrorKind.invalidResult,
          '图片接口返回了无效的 Base64 数据',
        );
      }
    }
    final payload = GeneratedImagePayload(
      url: url,
      bytes: bytes,
      revisedPrompt: first['revised_prompt']?.toString(),
    );
    if (!payload.isValid) {
      throw const ImageGenerationException(
        ImageGenerationErrorKind.invalidResult,
        '图片结果格式不兼容',
      );
    }
    return payload;
  }

  String _safeSize(int width, int height) {
    final requested = '${width}x$height';
    const supported = {'1024x1024', '1024x1536', '1536x1024'};
    return supported.contains(requested) ? requested : '1024x1024';
  }

  ImageGenerationException _httpError(int statusCode, String body) {
    if (statusCode == 401 || statusCode == 403) {
      return const ImageGenerationException(
        ImageGenerationErrorKind.invalidApiKey,
        'API Key 无效或没有访问权限',
      );
    }
    final message = _safeMessage(body).toLowerCase();
    if (statusCode == 404 || message.contains('model')) {
      return const ImageGenerationException(
        ImageGenerationErrorKind.modelUnavailable,
        '模型不存在或当前 API Key 无权使用',
      );
    }
    if (message.contains('image') || message.contains('generation')) {
      return const ImageGenerationException(
        ImageGenerationErrorKind.unsupportedGeneration,
        '当前模型不支持图片生成',
      );
    }
    return ImageGenerationException(
      ImageGenerationErrorKind.requestFailed,
      '图片生成请求失败（HTTP $statusCode）',
    );
  }

  String _safeMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final value = decoded['error']['message']?.toString() ?? '';
        return apiKey.isEmpty ? value : value.replaceAll(apiKey, '••••');
      }
    } catch (_) {}
    return '';
  }
}
