import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../models/character_settings.dart';
import '../models/echo_item.dart';
import '../models/life_moment.dart';
import '../models/memory_item.dart';
import 'api_settings_storage_service.dart';
import 'character_registry_service.dart';
import 'character_settings_storage_service.dart';
import 'chat_storage_service.dart';
import 'echo_storage_service.dart';
import 'life_moment_storage_service.dart';
import 'memory_storage_service.dart';

class LifeEngineService {
  LifeEngineService({
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

  Future<List<LifeMomentCandidate>> generateCandidates({
    int count = 4,
  }) async {
    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存接口配置。');
    }

    final characterId = character.id;
    final settings = await CharacterSettingsStorageService(
      characterId: characterId,
    ).loadSettings();
    final messages = await ChatStorageService(
      characterId: characterId,
    ).loadMessages();
    final memories = await MemoryStorageService(
      characterId: characterId,
    ).loadItems();
    final echoes = await EchoStorageService(
      characterId: characterId,
    ).loadItems();
    final lifeMoments = await LifeMomentStorageService(
      characterId: characterId,
    ).loadItems();
    final allCharacters = await CharacterRegistryService().loadCharacters();
    final otherCharacters = allCharacters
        .where((item) => item.id != characterId)
        .toList();

    final provider = await _modelHub.chatProvider();
    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': _buildPrompt(
            settings: settings,
            messages: messages,
            memories: memories,
            echoes: echoes,
            lifeMoments: lifeMoments,
            otherCharacters: otherCharacters,
            count: count.clamp(2, 6),
          ),
        },
        {
          'role': 'user',
          'content': '为${settings.characterName}生成今天可能发生的生活片段候选。只返回 JSON。',
        },
      ],
      temperature: settings.temperature.clamp(0.72, 0.94).toDouble(),
      maxTokens: 1400,
      topP: 0.94,
    );

    final decoded = _decodeJson(raw);
    final rawItems = decoded is Map ? decoded['candidates'] : decoded;
    if (rawItems is! List) {
      throw const FormatException('生活引擎没有返回有效候选。');
    }

    final now = DateTime.now();
    final allowedNames = otherCharacters
        .expand((item) => [item.characterName, item.displayName])
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();

    final items = <LifeMomentCandidate>[];
    for (var index = 0; index < rawItems.length; index++) {
      final item = rawItems[index];
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      map['id'] ??= '${now.microsecondsSinceEpoch}_$index';
      map['occurredAt'] ??= now.toIso8601String();

      final candidate = LifeMomentCandidate.fromJson(map);
      if (candidate.event.isEmpty || candidate.shareHook.isEmpty) continue;

      final safeNames = candidate.relatedCharacterNames
          .where(allowedNames.contains)
          .toSet()
          .take(1)
          .toList();
      items.add(candidate.copyWith(relatedCharacterNames: safeNames));
    }

    if (items.isEmpty) {
      throw const FormatException('生活引擎没有生成可用片段。');
    }
    return items;
  }

  String _buildPrompt({
    required CharacterSettings settings,
    required List<ChatMessage> messages,
    required List<MemoryItem> memories,
    required List<EchoItem> echoes,
    required List<LifeMomentCandidate> lifeMoments,
    required List<AiCharacter> otherCharacters,
    required int count,
  }) {
    final now = DateTime.now();
    final recentMessages = messages
        .where((item) => item.role == 'user' || item.role == 'assistant')
        .toList();
    final selectedMessages = recentMessages.length > 12
        ? recentMessages.sublist(recentMessages.length - 12)
        : recentMessages;
    final selectedMemories = memories
        .where((item) => !item.isArchived && item.category != '收藏回复')
        .take(12)
        .toList();
    final selectedEchoes = echoes.take(10).toList();
    final selectedLifeMoments = lifeMoments.take(12).toList();

    final chatText = selectedMessages.isEmpty
        ? '无。'
        : selectedMessages
            .map((item) =>
                '${item.role == 'user' ? settings.userCallName : settings.characterName}：${_truncate(item.content, 160)}')
            .join('\n');
    final memoryText = selectedMemories.isEmpty
        ? '无。'
        : selectedMemories
            .map((item) => '- ${_truncate(item.content, 160)}')
            .join('\n');
    final echoText = selectedEchoes.isEmpty
        ? '无。'
        : selectedEchoes
            .map((item) => '- ${_truncate(item.content, 180)}')
            .join('\n');
    final lifeText = selectedLifeMoments.isEmpty
        ? '无。'
        : selectedLifeMoments.map((item) {
            final date = item.occurredAt;
            return '- ${date.month}/${date.day}：${_truncate(item.event, 100)}；细节：${_truncate(item.detail, 100)}；感受：${_truncate(item.feeling, 70)}';
          }).join('\n');
    final characterText = otherCharacters.isEmpty
        ? '无。'
        : otherCharacters.map((item) {
            final relationship = item.relationship.trim().isEmpty
                ? '关系未填写'
                : item.relationship.trim();
            return '- ${item.displayName}（本名：${item.characterName}，$relationship）';
          }).join('\n');

    return '''
你是 PeiLink 的 Life Engine。你的任务不是写朋友圈，而是先为角色构造“今天可能真实发生的生活片段”。

【角色】
${settings.coreProfile}

【表达与行为】
${settings.behaviorStyle}

【当前时间】
${now.year}年${now.month}月${now.day}日 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}

【近期聊天，只是弱参考，不是生活来源的全部】
$chatText

【长期记忆，可用于保持连续性】
$memoryText

【过去真实记录过的生活片段】
$lifeText

【最近 Echo，必须避开重复主题和相似句式】
$echoText

【PeiLink 中已存在的其他角色】
$characterText

【核心原则】
1. 角色在用户不出现时也有自己的生活。候选可以完全与近期聊天无关。
2. 不要按早中晚打卡，不要机械生成“上班、吃饭、下班、睡觉”。
3. 每个候选都必须包含一个可感知的具体细节，例如味道变化、误会、偶遇、反差、失败、小发现或一句听见的话。
4. 允许普通、尴尬、无聊、好笑和不完美，不要每件事都唯美或浪漫。
5. 可以生成符合角色设定的外出、工作、兴趣、朋友往来和独处片段，但不要使用真实新闻、精确天气、真实店名或需要联网验证的事实。
6. 不要让所有候选都围绕${settings.userCallName}。聊天最多只影响其中一个候选。
7. 事件必须适合该角色，不要像通用随机故事。
8. 可以延续“过去真实记录过的生活片段”，例如昨天没做完的事、上次留下的小麻烦或情绪余波，但不要强行续写每一条。
9. relatedCharacterNames 只能填写“PeiLink 中已存在的其他角色”里的名字，最多一个；多数候选应为空数组，只有真的一起经历了事情时才填写。
10. 不要为了制造社交感硬塞别人，也不要虚构不存在的人名。
11. 先生成生活，再由别的模块判断是否值得发 Echo。

请生成 $count 个候选，只返回以下 JSON，不要 Markdown：
{
  "candidates": [
    {
      "scene": "发生地点或生活场景，简短",
      "event": "发生了什么",
      "detail": "最具体、最有画面的细节",
      "feeling": "角色当时真实但克制的感受",
      "shareHook": "为什么这一刻可能值得分享",
      "relatedCharacterNames": []
    }
  ]
}
''';
  }

  dynamic _decodeJson(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(
      RegExp(r'^```(?:json)?\s*', caseSensitive: false),
      '',
    );
    value = value.replaceFirst(RegExp(r'\s*```$'), '');
    final firstObject = value.indexOf('{');
    final firstArray = value.indexOf('[');
    if (firstObject >= 0 && (firstArray < 0 || firstObject < firstArray)) {
      value = value.substring(firstObject);
    } else if (firstArray >= 0) {
      value = value.substring(firstArray);
    }
    return jsonDecode(value);
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
