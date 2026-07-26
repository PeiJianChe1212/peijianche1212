import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/character_settings.dart';
import '../models/echo_item.dart';
import '../models/life_moment.dart';
import 'api_settings_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'echo_storage_service.dart';
import 'context_builder.dart';

class MomentEngineService {
  MomentEngineService({
    required this.character,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null {
    _modelHub = ModelHub(client: _client);
  }

  final AiCharacter character;
  final http.Client _client;
  final bool _ownsClient;
  late final ModelHub _modelHub;

  final ApiSettingsStorageService _apiStorage = ApiSettingsStorageService();

  Future<EchoMomentDecision> chooseMoment(
    List<LifeMomentCandidate> candidates, {
    bool manualRequest = false,
  }) async {
    if (candidates.isEmpty) {
      throw ArgumentError.value(candidates, 'candidates', '候选不能为空');
    }

    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存接口配置。');
    }

    final settings = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();
    final echoes = await EchoStorageService(
      characterId: character.id,
    ).loadItems();
    final provider = await _modelHub.chatProvider();

    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': ContextBuilder.build(
            task: ContextTask.momentSelection,
            settings: settings,
            taskRules: _buildPrompt(
            settings: settings,
            candidates: candidates,
            echoes: echoes.take(12).toList(),
            manualRequest: manualRequest,
          ),
          ),
        },
        {
          'role': 'user',
          'content': '判断这些生活片段中是否存在值得发布到 Echo 的瞬间。只返回 JSON。',
        },
      ],
      temperature: 0.42,
      maxTokens: 520,
      topP: 0.82,
    );

    final decoded = _decodeObject(raw);
    final index = _readInt(decoded['selectedIndex'], 0)
        .clamp(0, candidates.length - 1)
        .toInt();
    final score = _readDouble(decoded['score'], 0).clamp(0, 100).toDouble();
    final modelShouldShare = decoded['shouldShare'] == true;
    final shouldShare = manualRequest
        ? score >= 48 || modelShouldShare
        : score >= 72 && modelShouldShare;

    return EchoMomentDecision(
      shouldShare: shouldShare,
      score: score,
      reason: decoded['reason']?.toString().trim() ?? '',
      candidate: candidates[index],
      suggestImage: decoded['suggestImage'] == true,
    );
  }

  String _buildPrompt({
    required CharacterSettings settings,
    required List<LifeMomentCandidate> candidates,
    required List<EchoItem> echoes,
    required bool manualRequest,
  }) {
    final candidateText = candidates.asMap().entries.map((entry) {
      final item = entry.value;
      return '''
[${entry.key}]
场景：${item.scene}
事件：${item.event}
细节：${item.detail}
感受：${item.feeling}
分享钩子：${item.shareHook}
''';
    }).join('\n');

    final echoText = echoes.isEmpty
        ? '无。'
        : echoes.map((item) => '- ${_truncate(item.content, 180)}').join('\n');

    return '''
你是 PeiLink 的 Moment Engine。你不是负责凑更新频率，而是判断生活里有没有“值得分享的瞬间”。

【候选片段】
$candidateText

【最近发布过的 Echo】
$echoText

【判断标准】
高分瞬间通常至少具备两项：
- 一个只有亲历者才会注意到的具体细节；
- 轻微反差、意外、糗事、发现或情绪余味；
- 能体现角色本人的目光和性格；
- 即使不了解前文，也能单独成立；
- 与最近 Echo 不重复；
- 读完会让人觉得“这件小事确实值得他记一下”。

低分内容包括：
- 单纯报时、报行程、报状态；
- “今天上班了”“吃饭了”“下班了”“有点累”；
- 空泛抒情、万能鸡汤、强行浪漫；
- 只是把近期聊天换一种说法；
- 为了发而发，没有具体细节。

${manualRequest ? '当前是用户主动点击生成草稿，可以适当放宽，但仍要选出最有记忆点的一条。' : '当前是自动判断。宁可不发，也不要拿普通日程凑数。'}

只返回 JSON：
{
  "shouldShare": true,
  "selectedIndex": 0,
  "score": 0,
  "reason": "一句话说明这个瞬间为什么值得或不值得分享",
  "suggestImage": false
}
''';
  }

  Map<String, dynamic> _decodeObject(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(
      RegExp(r'^```(?:json)?\s*', caseSensitive: false),
      '',
    );
    value = value.replaceFirst(RegExp(r'\s*```$'), '');
    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start >= 0 && end > start) {
      value = value.substring(start, end + 1);
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Moment Engine 返回格式不正确。');
    }
    return Map<String, dynamic>.from(decoded);
  }

  int _readInt(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _readDouble(dynamic value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _truncate(String value, int maxLength) {
    final clean = value.trim();
    if (clean.length <= maxLength) return clean;
    return '${clean.substring(0, maxLength)}…';
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
