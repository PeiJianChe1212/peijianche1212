import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../models/causal_node.dart';
import '../models/character_settings.dart';
import '../models/echo_item.dart';
import '../models/life_decision.dart';
import '../models/life_moment.dart';
import '../models/memory_item.dart';
import 'api_settings_storage_service.dart';
import 'character_settings_storage_service.dart';
import 'character_registry_service.dart';
import 'character_relationship_context_service.dart';
import 'chat_storage_service.dart';
import 'causal_graph_service.dart';
import 'decision_history_service.dart';
import 'context_builder.dart';
import 'echo_storage_service.dart';
import 'life_decision_engine_service.dart';
import 'life_event_renderer_service.dart';
import 'life_moment_storage_service.dart';
import 'memory_storage_service.dart';
import 'ai_social_protocol_service.dart';
import 'shared_experience_service.dart';
import 'shared_world_resource_service.dart';
import 'structured_model_output_exception.dart';

class LifeEngineService {
  LifeEngineService({required this.character, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null {
    _modelHub = ModelHub(client: _client);
  }

  final AiCharacter character;
  final http.Client _client;
  final bool _ownsClient;
  late final ModelHub _modelHub;

  final ApiSettingsStorageService _apiStorage = ApiSettingsStorageService();

  /// 兼容旧调用入口。
  ///
  /// 新链路会先经过 Life Decision Engine，再由 Life Engine 把已经确定
  /// 发生的事情生成成具体生活事件。
  Future<List<LifeMomentCandidate>> generateCandidates({int count = 4}) async {
    final decisionEngine = LifeDecisionEngineService(
      character: character,
      client: _client,
    );
    final decisions = await decisionEngine.decide(
      maxDecisions: count.clamp(1, 4),
    );
    return generateFromDecisions(decisions);
  }

  /// 把已经确定发生的 LifeDecision 生成成具体生活内容。
  ///
  /// 此处不能改变决定本身，也不能创造决定之外的天气、地点、店铺、
  /// NPC、新闻或公共事件。
  Future<List<LifeMomentCandidate>> generateFromDecisions(
    List<LifeDecision> decisions,
  ) async {
    if (decisions.isEmpty) return const [];

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
    final relationshipPrompt = await CharacterRelationshipContextService()
        .buildPromptSection(
          currentCharacter: character,
          allCharacters: allCharacters,
        );

    final provider = await _modelHub.chatProvider();
    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': ContextBuilder.build(
            task: ContextTask.lifeGeneration,
            settings: settings,
            taskRules: _buildPrompt(
              settings: settings,
              messages: messages,
              memories: memories,
              echoes: echoes,
              lifeMoments: lifeMoments,
              decisions: decisions,
              relationshipPrompt: relationshipPrompt,
            ),
            relationshipContext: relationshipPrompt,
            socialProtocol: AiSocialProtocolService.compactRules,
          ),
        },
        {'role': 'user', 'content': '把这些已经确定发生的决定生成成具体生活事件。只返回 JSON。'},
      ],
      temperature: settings.temperature.clamp(0.58, 0.78).toDouble(),
      maxTokens: 1500,
      topP: 0.9,
      acceptStructuredReasoningFallback: true,
    );

    final decoded = _decodeJson(raw);
    final rawItems = decoded is Map ? decoded['events'] : decoded;
    if (rawItems is! List) {
      throw const FormatException('生活引擎没有返回有效事件。');
    }

    final decisionById = {
      for (final decision in decisions) decision.id: decision,
    };
    final now = DateTime.now();
    final items = const LifeEventRendererService().render(
      rawItems: rawItems,
      decisions: decisions,
      now: now,
    );

    await _persistLifeCauses(items, decisionsById: decisionById, now: now);
    await DecisionHistoryService(
      characterId: characterId,
    ).markMaterialized(items.map((item) => item.decisionId), now: now);
    final resourceService = SharedWorldResourceService();
    for (final decisionId in items.map((item) => item.decisionId).toSet()) {
      await resourceService.commitDecision(decisionId, now: now);
    }

    final sharedExperienceService = SharedExperienceService();
    for (final item in items) {
      for (final relatedName in item.relatedCharacterNames.toSet()) {
        AiCharacter? relatedCharacter;
        for (final candidate in allCharacters) {
          if (candidate.id == character.id) continue;
          if (candidate.characterName == relatedName ||
              candidate.displayName == relatedName) {
            relatedCharacter = candidate;
            break;
          }
        }
        if (relatedCharacter == null) continue;
        await sharedExperienceService.recordLifeEvent(
          currentCharacter: character,
          relatedCharacter: relatedCharacter,
          event: item,
        );
      }
    }
    return items;
  }

  Future<void> _persistLifeCauses(
    List<LifeMomentCandidate> events, {
    required Map<String, LifeDecision> decisionsById,
    required DateTime now,
  }) async {
    if (events.isEmpty) return;
    final nodes = events.map((event) {
      final decision = decisionsById[event.decisionId];
      final parentId = decision?.causeNodeId.trim() ?? '';
      return CausalNode(
        id: event.causeNodeId,
        type: CausalNodeType.lifeEvent,
        sourceId: event.id,
        title: event.event,
        detail: event.detail,
        occurredAt: event.occurredAt,
        createdAt: now,
        parentIds: parentId.isEmpty ? const [] : [parentId],
        characterId: character.id,
        metadata: {
          'scene': event.scene,
          'feeling': event.feeling,
          'decisionId': event.decisionId,
          'decisionSummary': event.decisionSummary,
          'decisionReason': event.decisionReason,
          'worldEventIds': event.worldEventIds,
          'resourceClaims': event.resourceClaims,
          'renderedAt': event.renderedAt?.toIso8601String(),
          'rendererVersion': event.rendererVersion,
          'relationshipOpportunityId': event.relationshipOpportunityId,
        },
      );
    }).toList();
    await CausalGraphService().upsertAll(nodes, now: now);
  }

  String _buildPrompt({
    required CharacterSettings settings,
    required List<ChatMessage> messages,
    required List<MemoryItem> memories,
    required List<EchoItem> echoes,
    required List<LifeMomentCandidate> lifeMoments,
    required List<LifeDecision> decisions,
    required String relationshipPrompt,
  }) {
    final recentMessages = messages
        .where((item) => item.role == 'user' || item.role == 'assistant')
        .toList();
    final selectedMessages = recentMessages.length > 8
        ? recentMessages.sublist(recentMessages.length - 8)
        : recentMessages;
    final selectedMemories = memories
        .where((item) => !item.isArchived && item.category != '收藏回复')
        .take(10)
        .toList();
    final selectedEchoes = echoes.take(8).toList();
    final selectedLifeMoments = lifeMoments.take(10).toList();

    final decisionText = decisions
        .map((decision) {
          final names = decision.relatedCharacterNames.isEmpty
              ? '无'
              : decision.relatedCharacterNames.join('、');
          return '''
- decisionId：${decision.id}
  确定事项：${decision.summary}
  因果：${decision.reason}
  发生时间：${decision.scheduledAt.toIso8601String()}
  已知地点：${decision.location.isEmpty ? '未知' : decision.location}
  相关角色：$names
  关系机会：${decision.relationshipOpportunityId.isEmpty ? '无' : decision.relationshipOpportunityId}
''';
        })
        .join('\n');

    final chatText = selectedMessages.isEmpty
        ? '无。'
        : selectedMessages
              .map((item) {
                final speaker = item.role == 'user'
                    ? settings.userCallName
                    : settings.characterName;
                return '$speaker：${_truncate(item.content, 120)}';
              })
              .join('\n');
    final memoryText = selectedMemories.isEmpty
        ? '无。'
        : selectedMemories
              .map((item) => '- ${_truncate(item.content, 140)}')
              .join('\n');
    final echoText = selectedEchoes.isEmpty
        ? '无。'
        : selectedEchoes
              .map((item) => '- ${_truncate(item.content, 150)}')
              .join('\n');
    final lifeText = selectedLifeMoments.isEmpty
        ? '无。'
        : selectedLifeMoments
              .map((item) {
                return '- ${item.occurredAt.month}/${item.occurredAt.day}：'
                    '${_truncate(item.event, 100)}；${_truncate(item.detail, 90)}';
              })
              .join('\n');

    return '''
你是 PeiLink 的 Life Engine。
上游 Life Decision Engine 已经决定了哪些事情会发生。
你只负责把这些决定落实为具体、自然、符合角色的生活事件。

【已经确定发生的决定】
$decisionText

【过去已经发生的生活，用于保持连续性】
$lifeText

【长期记忆】
$memoryText

【近期聊天，只能影响细微反应】
$chatText

【最近 Echo，避免重复细节和表达】
$echoText


【生成边界】
1. 每个输出必须对应一个真实存在的 decisionId，一条决定最多生成一条事件。
2. 不得取消、替换或改写决定的核心事实，也不得把“确定发生”改成“可能发生”。
3. 不得创造决定之外的天气、真实店名、NPC、新闻、节日、公共事件或地图变化。
4. scene 只能使用决定中已有地点；地点未知时写普通室内、住处、路上等不新增世界事实的场景。
5. event 写已经发生了什么；detail 写一个可感知的具体细节；feeling 写克制真实的感受。
6. shareHook 只说明这一刻可能值得记录的原因，不代表一定会发 Echo。
7. 可以补充动作、物品、味道、声音、微小失败和反差，但补充内容必须服务于原决定。
8. 不要把事件写成小说，不要强行浪漫，不要把每件事都变得特别。
9. relatedCharacterNames 由系统固定，不要自行增删。
10. 多角色共同参与时，写自然分工与不同反应，不自动生成吃醋、争吵、抢人或评论区对线。
11. 只输出对应事件；无法安全落实某个决定时可以跳过，不要编造补洞。

只返回以下 JSON，不要 Markdown：
{
  "events": [
    {
      "decisionId": "对应的 decisionId",
      "scene": "发生场景",
      "event": "已经发生的事情",
      "detail": "最具体的生活细节",
      "feeling": "角色真实而克制的感受",
      "shareHook": "为什么这一刻可能值得记录"
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
    return decodeStructuredModelJson(value, stage: 'Life Engine');
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
