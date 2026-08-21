import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'vision_adapter.dart';

/// Preserves the request semantics of PeiLink's previously verified
/// Volcengine multimodal implementation. For Ark, [endpointId] is sent in the
/// protocol's `model` field, but remains an Endpoint ID in PeiLink's UI/domain.
class VolcengineVisionAdapter implements VisionAdapter {
  VolcengineVisionAdapter({
    required this.apiKey,
    required this.endpointUrl,
    required this.endpointId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get adapterName => '豆包 / 火山方舟';

  final String apiKey;
  final String endpointUrl;
  final String endpointId;
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
    return understandImageBytes(
      bytes: await file.readAsBytes(),
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
    if (endpointId.trim().isEmpty) {
      throw const VisionException(
        VisionErrorKind.modelUnavailable,
        '请先填写火山方舟 Endpoint ID',
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
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:$mimeType;base64,${base64Encode(bytes)}',
            },
          },
          {'type': 'text', 'text': instruction.trim()},
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
              'model': endpointId.trim(),
              'messages': messages,
              'stream': false,
              'max_tokens': maxTokens,
              'temperature': 0.35,
            }),
          )
          .timeout(const Duration(seconds: 60));
      final body = utf8.decode(response.bodyBytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _httpError(response.statusCode, body);
      }
      final decoded = jsonDecode(body);
      final choices = decoded is Map ? decoded['choices'] : null;
      final first = choices is List && choices.isNotEmpty
          ? choices.first
          : null;
      final message = first is Map ? first['message'] : null;
      final content = message is Map
          ? message['content']?.toString().trim() ?? ''
          : '';
      if (content.isEmpty) {
        throw const VisionException(
          VisionErrorKind.incompatibleProtocol,
          '火山方舟图片理解接口返回格式异常',
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
        '火山方舟图片理解接口返回格式异常',
      );
    }
  }

  VisionException _httpError(int statusCode, String body) {
    final message = _safeErrorMessage(body).toLowerCase();
    if (statusCode == 401) {
      return const VisionException(VisionErrorKind.invalidApiKey, 'API Key 无效');
    }
    if (statusCode == 403) {
      return const VisionException(VisionErrorKind.permissionDenied, '没有该模型权限');
    }
    if (_explicitlyRejectsImageInput(message)) {
      return const VisionException(
        VisionErrorKind.unsupportedImageInput,
        '当前模型不支持图片输入',
      );
    }
    if (statusCode == 404 ||
        message.contains('endpoint not found') ||
        message.contains('model not found')) {
      return const VisionException(
        VisionErrorKind.modelUnavailable,
        'Endpoint 不存在或不可用',
      );
    }
    if (statusCode == 400) {
      return const VisionException(
        VisionErrorKind.incompatibleProtocol,
        '火山方舟请求协议或参数不兼容',
      );
    }
    return VisionException(
      VisionErrorKind.requestFailed,
      '图片理解请求失败（HTTP $statusCode）',
    );
  }

  bool _explicitlyRejectsImageInput(String message) =>
      message.contains('does not support image') ||
      message.contains('image input is not supported') ||
      message.contains('unsupported image input') ||
      message.contains('不支持图片输入') ||
      message.contains('不支持图像输入');

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
