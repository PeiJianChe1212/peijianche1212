import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/api_settings.dart';

class AvailableModel {
  const AvailableModel({
    required this.id,
    required this.displayName,
    required this.provider,
  });

  final String id;
  final String displayName;
  final AIProvider provider;
}

enum ModelDiscoveryErrorKind {
  invalidApiKey,
  invalidBaseUrl,
  networkUnavailable,
  timeout,
  incompatibleResponse,
  unsupported,
  requestFailed,
}

class ModelDiscoveryException implements Exception {
  const ModelDiscoveryException(this.kind, this.userMessage);

  final ModelDiscoveryErrorKind kind;
  final String userMessage;

  @override
  String toString() => userMessage;
}

class ModelDiscoveryService {
  ModelDiscoveryService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Map<String, _CachedModels> _cache = {};

  Future<List<AvailableModel>> discover({
    required AIProvider provider,
    required String apiKey,
    required String baseUrl,
    bool forceRefresh = false,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const ModelDiscoveryException(
        ModelDiscoveryErrorKind.invalidApiKey,
        '请先填写 API Key',
      );
    }
    if (provider == AIProvider.volcengine) {
      throw const ModelDiscoveryException(
        ModelDiscoveryErrorKind.unsupported,
        '火山方舟推理 API Key 无法直接列出账号 Endpoint，请手动填写 Endpoint ID',
      );
    }

    final effectiveBaseUrl = baseUrl.trim().isNotEmpty
        ? baseUrl.trim()
        : provider.officialBaseUrl;
    late final String url;
    try {
      url = ApiEndpointResolver.modelsUrl(effectiveBaseUrl);
    } on FormatException {
      throw const ModelDiscoveryException(
        ModelDiscoveryErrorKind.invalidBaseUrl,
        'Base URL 格式不正确',
      );
    }

    final cacheKey = '${provider.name}|$url';
    final cached = _cache[cacheKey];
    if (!forceRefresh && cached != null && cached.apiKey == apiKey.trim()) {
      return cached.models;
    }

    try {
      final response = await _client
          .get(
            Uri.parse(url),
            headers: {'Authorization': 'Bearer ${apiKey.trim()}'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ModelDiscoveryException(
          ModelDiscoveryErrorKind.invalidApiKey,
          'API Key 无效或没有获取模型列表的权限',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ModelDiscoveryException(
          response.statusCode == 404
              ? ModelDiscoveryErrorKind.invalidBaseUrl
              : ModelDiscoveryErrorKind.requestFailed,
          response.statusCode == 404
              ? '模型列表地址不存在，请检查 Base URL'
              : '模型列表获取失败（HTTP ${response.statusCode}）',
        );
      }
      final models = parseModels(response.body, provider);
      if (models.isEmpty && provider == AIProvider.deepseek) {
        return deepSeekFallbackModels;
      }
      if (models.isEmpty) {
        throw const ModelDiscoveryException(
          ModelDiscoveryErrorKind.incompatibleResponse,
          '接口没有返回可用的聊天模型',
        );
      }
      final result = List<AvailableModel>.unmodifiable(models);
      _cache[cacheKey] = _CachedModels(apiKey.trim(), result);
      return result;
    } on ModelDiscoveryException {
      if (provider == AIProvider.deepseek) return deepSeekFallbackModels;
      rethrow;
    } on TimeoutException {
      if (provider == AIProvider.deepseek) return deepSeekFallbackModels;
      throw const ModelDiscoveryException(
        ModelDiscoveryErrorKind.timeout,
        '获取模型列表超时，请检查网络后重试',
      );
    } on SocketException {
      if (provider == AIProvider.deepseek) return deepSeekFallbackModels;
      throw const ModelDiscoveryException(
        ModelDiscoveryErrorKind.networkUnavailable,
        '网络不可用，无法连接模型服务',
      );
    } on FormatException {
      if (provider == AIProvider.deepseek) return deepSeekFallbackModels;
      throw const ModelDiscoveryException(
        ModelDiscoveryErrorKind.incompatibleResponse,
        '模型列表接口返回格式不兼容',
      );
    } on http.ClientException {
      if (provider == AIProvider.deepseek) return deepSeekFallbackModels;
      throw const ModelDiscoveryException(
        ModelDiscoveryErrorKind.networkUnavailable,
        '无法连接模型服务，请检查网络或 Base URL',
      );
    }
  }

  static List<AvailableModel> parseModels(String body, AIProvider provider) {
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['data'] is! List) {
      throw const FormatException('missing data');
    }
    final result = <AvailableModel>[];
    final seen = <String>{};
    for (final item in decoded['data'] as List) {
      if (item is! Map) continue;
      final id = item['id']?.toString().trim() ?? '';
      if (id.isEmpty || !seen.add(id) || !_looksLikeChatModel(id)) continue;
      result.add(AvailableModel(id: id, displayName: id, provider: provider));
    }
    result.sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  static bool _looksLikeChatModel(String id) {
    final value = id.toLowerCase();
    const excluded = [
      'embedding',
      'moderation',
      'tts',
      'speech',
      'transcri',
      'whisper',
      'image',
      'dall-e',
      'realtime',
    ];
    return !excluded.any(value.contains);
  }

  static const deepSeekFallbackModels = <AvailableModel>[
    AvailableModel(
      id: 'deepseek-chat',
      displayName: 'DeepSeek Chat',
      provider: AIProvider.deepseek,
    ),
    AvailableModel(
      id: 'deepseek-reasoner',
      displayName: 'DeepSeek Reasoner',
      provider: AIProvider.deepseek,
    ),
  ];

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class _CachedModels {
  const _CachedModels(this.apiKey, this.models);

  final String apiKey;
  final List<AvailableModel> models;
}
