import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'vision_adapter.dart';

class OpenAiCompatibleVisionAdapter implements VisionAdapter {
  OpenAiCompatibleVisionAdapter({
    required this.adapterName,
    required this.apiKey,
    required this.endpointUrl,
    required this.model,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  final String adapterName;
  final String apiKey;
  final String endpointUrl;
  final String model;
  final http.Client _client;

  @override
  Future<String> understandImagePath({
    required String imagePath,
    required String instruction,
    String? systemPrompt,
    int maxTokens = 900,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw const VisionException(VisionErrorKind.invalidImage, '找不到需要识别的图片');
    }
    final bytes = await file.readAsBytes();
    return understandImageBytes(
      bytes: bytes,
      mimeType: _mimeTypeForPath(imagePath),
      instruction: instruction,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<String> understandImageBytes({
    required Uint8List bytes,
    required String mimeType,
    required String instruction,
    String? systemPrompt,
    int maxTokens = 900,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const VisionException(
        VisionErrorKind.invalidApiKey,
        '请先填写图片理解 API Key',
      );
    }
    if (model.trim().isEmpty) {
      throw const VisionException(
        VisionErrorKind.modelUnavailable,
        '请先选择图片理解模型',
      );
    }
    if (bytes.isEmpty) {
      throw const VisionException(VisionErrorKind.invalidImage, '测试图片为空');
    }
    final messages = <Map<String, dynamic>>[
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
        {'role': 'system', 'content': systemPrompt.trim()},
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': instruction.trim()},
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:$mimeType;base64,${base64Encode(bytes)}',
            },
          },
        ],
      },
    ];
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
              'messages': messages,
              'stream': false,
              'max_tokens': maxTokens,
              'temperature': 0,
            }),
          )
          .timeout(const Duration(seconds: 45));
      final body = utf8.decode(response.bodyBytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _httpError(response.statusCode, body);
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['choices'] is! List) {
        throw const VisionException(
          VisionErrorKind.incompatibleProtocol,
          '接口不支持 OpenAI Compatible 图片理解协议',
        );
      }
      final choices = decoded['choices'] as List;
      if (choices.isEmpty || choices.first is! Map) {
        throw const VisionException(
          VisionErrorKind.incompatibleProtocol,
          '图片理解接口没有返回有效内容',
        );
      }
      final message = (choices.first as Map)['message'];
      final content = message is Map
          ? message['content']?.toString().trim() ?? ''
          : '';
      if (content.isEmpty) {
        throw const VisionException(
          VisionErrorKind.incompatibleProtocol,
          '图片理解接口返回了空内容',
        );
      }
      return content;
    } on VisionException {
      rethrow;
    } on TimeoutException {
      throw const VisionException(VisionErrorKind.timeout, '图片理解请求超时');
    } on SocketException {
      throw const VisionException(
        VisionErrorKind.networkUnavailable,
        '网络不可用，无法连接图片理解服务',
      );
    } on http.ClientException {
      throw const VisionException(
        VisionErrorKind.networkUnavailable,
        '无法连接图片理解服务',
      );
    } on FormatException {
      throw const VisionException(
        VisionErrorKind.incompatibleProtocol,
        '图片理解接口返回格式不兼容',
      );
    }
  }

  VisionException _httpError(int statusCode, String body) {
    if (statusCode == 401) {
      return const VisionException(VisionErrorKind.invalidApiKey, 'API Key 无效');
    }
    if (statusCode == 403) {
      return const VisionException(VisionErrorKind.permissionDenied, '没有该模型权限');
    }
    final message = _safeErrorMessage(body);
    final lower = message.toLowerCase();
    if (lower.contains('does not support image') ||
        lower.contains('image input is not supported') ||
        lower.contains('unsupported image input') ||
        lower.contains('不支持图片输入') ||
        lower.contains('不支持图像输入')) {
      return const VisionException(
        VisionErrorKind.unsupportedImageInput,
        '当前模型不支持图片输入',
      );
    }
    if (statusCode == 404 || lower.contains('model')) {
      return const VisionException(
        VisionErrorKind.modelUnavailable,
        '模型不存在或当前 API Key 无权使用',
      );
    }
    return VisionException(
      VisionErrorKind.requestFailed,
      '图片理解请求失败（HTTP $statusCode）',
    );
  }

  String _safeErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final value = decoded['error']['message']?.toString() ?? '';
        return apiKey.isEmpty ? value : value.replaceAll(apiKey, '••••');
      }
    } catch (_) {}
    return '';
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}
