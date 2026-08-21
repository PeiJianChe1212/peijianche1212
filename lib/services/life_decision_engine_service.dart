import 'package:http/http.dart' as http;

import '../ai/model_hub.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../models/causal_node.dart';
import '../models/character_settings.dart';
import '../models/life_decision.dart';
import '../models/life_moment.dart';
import '../models/memory_item.dart';
import '../models/world_event.dart';
import '../models/world_resource.dart';
import 'api_settings_storage_service.dart';
import 'character_registry_service.dart';
import 'character_relationship_context_service.dart';
import 'character_settings_storage_service.dart';
import 'chat_storage_service.dart';
import 'causal_graph_service.dart';
import 'decision_history_service.dart';
import 'context_builder.dart';
import 'life_moment_storage_service.dart';
import 'memory_storage_service.dart';
import 'relationship_opportunity_engine_service.dart';
import 'ai_social_protocol_service.dart';
import 'shared_world_resource_service.dart';
import 'structured_model_output_exception.dart';
import 'world_timeline_service.dart';

class LifeDecisionEngineService {
  LifeDecisionEngineService({required this.character, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null {
    _modelHub = ModelHub(client: _client);
  }

  final AiCharacter character;
  final http.Client _client;
  final bool _ownsClient;
  late final ModelHub _modelHub;

  final ApiSettingsStorageService _apiStorage = ApiSettingsStorageService();
  final WorldTimelineService _worldTimeline = WorldTimelineService();
  final CausalGraphService _causalGraph = CausalGraphService();
  final SharedWorldResourceService _resourceService =
      SharedWorldResourceService();

  Future<List<LifeDecision>> decide({
    int maxDecisions = 3,
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    final apiSettings = await _apiStorage.loadSettings();
    if (!apiSettings.isConfigured) {
      throw StateError('请先在“设置 → 模型与 API”中填写并保存接口配置。');
    }

    await _worldTimeline.ensureCurrentTimeState(now: time);
    final worldEvents = await _worldTimeline.loadDecisionWindow(
      now: time,
      characterId: character.id,
      limit: 40,
    );
    await _resourceService.syncFromWorldEvents(worldEvents, now: time);
    final worldResources = await _resourceService.loadAvailable(now: time);

    final settings = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();
    final messages = await ChatStorageService(
      characterId: character.id,
    ).loadMessages();
    final memories = await MemoryStorageService(
      characterId: character.id,
    ).loadItems();
    final lifeMoments = await LifeMomentStorageService(
      characterId: character.id,
    ).loadItems();
    final decisionHistory = await DecisionHistoryService(
      characterId: character.id,
    ).loadRecent(now: time, limit: 12);
    final allCharacters = await CharacterRegistryService().loadCharacters();
    final otherCharacters = allCharacters
        .where((item) => item.id != character.id)
        .toList();
    final relationshipPrompt = await CharacterRelationshipContextService()
        .buildPromptSection(
          currentCharacter: character,
          allCharacters: allCharacters,
        );
    final opportunityEngine = RelationshipOpportunityEngineService();
    final relationshipOpportunities = await opportunityEngine.evaluate(
      currentCharacter: character,
      allCharacters: allCharacters,
      worldEvents: worldEvents,
      now: time,
    );
    final opportunityPrompt = opportunityEngine.buildPromptSection(
      relationshipOpportunities,
    );

    final provider = await _modelHub.chatProvider();
    final raw = await provider.complete(
      messages: [
        {
          'role': 'system',
          'content': ContextBuilder.build(
            task: ContextTask.lifeDecision,
            settings: settings,
            taskRules: _buildPrompt(
              settings: settings,
              messages: messages,
              memories: memories,
              lifeMoments: lifeMoments,
              otherCharacters: otherCharacters,
              relationshipPrompt: relationshipPrompt,
              worldEvents: worldEvents,
              decisionHistory: decisionHistory,
              worldResources: worldResources,
              now: time,
              maxDecisions: maxDecisions.clamp(1, 4),
              relationshipOpportunityPrompt: opportunityPrompt,
            ),
            relationshipContext: '$relationshipPrompt\n\n$opportunityPrompt',
            socialProtocol: AiSocialProtocolService.buildPromptSection(
              currentCharacter: character,
              allCharacters: [character, ...otherCharacters],
            ),
          ),
        },
        {
          'role': 'user',
          'content': '判断${settings.characterName}接下来真正应该发生什么。只返回 JSON。',
        },
      ],
      temperature: 0.45,
      maxTokens: 1200,
      topP: 0.86,
      acceptStructuredReasoningFallback: true,
    );

    final decoded = _decodeJson(raw);
    final rawItems = decoded is Map ? decoded['decisions'] : decoded;
    if (rawItems is! List) {
      throw const FormatException('生活决策引擎没有返回有效结果。');
    }

    final allowedWorldIds = worldEvents.map((item) => item.id).toSet();

    final decisions = <LifeDecision>[];
    for (var index = 0; index < rawItems.length; index++) {
      final item = rawItems[index];
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      map['id'] ??= 'decision_${time.microsecondsSinceEpoch}_$index';
      map['characterId'] = character.id;
      map['decidedAt'] = time.toIso8601String();

      final decision = LifeDecision.fromJson(map);
      if (decision.summary.isEmpty || decision.reason.isEmpty) continue;

      final latestAllowed = time.add(const Duration(hours: 24));
      if (!decision.scheduledAt.isAfter(time) ||
          decision.scheduledAt.isAfter(latestAllowed)) {
        continue;
      }

      final safeWorldIds = decision.worldEventIds
          .where(allowedWorldIds.contains)
          .toSet()
          .toList();
      final selectedOpportunity = opportunityEngine.validateSelection(
        opportunityId: decision.relationshipOpportunityId,
        requestedNames: decision.relatedCharacterNames,
        opportunities: relationshipOpportunities,
      );
      final safeNames = selectedOpportunity == null
          ? const <String>[]
          : <String>[selectedOpportunity.otherCharacterName];

      final allowedResourceIds = worldResources.map((item) => item.id).toSet();
      final safeClaims = <String, int>{};
      for (final entry in decision.resourceClaims.entries) {
        if (!allowedResourceIds.contains(entry.key) || entry.value <= 0) {
          continue;
        }
        safeClaims[entry.key] = entry.value;
      }

      final causeNodeId = 'cause_decision_${decision.id}';
      final safeDecision = decision.copyWith(
        worldEventIds: safeWorldIds,
        relatedCharacterNames: safeNames,
        resourceClaims: safeClaims,
        causeNodeId: causeNodeId,
        relationshipOpportunityId: selectedOpportunity?.id ?? '',
      );
      final reserved = await _resourceService.reserve(
        decisionId: safeDecision.id,
        characterId: character.id,
        claims: safeDecision.resourceClaims,
        scheduledAt: safeDecision.scheduledAt,
        now: time,
      );
      if (reserved) {
        decisions.add(safeDecision);
        if (selectedOpportunity != null) {
          await opportunityEngine.markSelected(selectedOpportunity, now: time);
        }
      }
      if (decisions.length >= maxDecisions.clamp(1, 4)) break;
    }

    decisions.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final selected = decisions.take(maxDecisions.clamp(1, 4)).toList();
    await _persistDecisionCauses(
      decisions: selected,
      worldEvents: worldEvents,
      now: time,
    );
    await DecisionHistoryService(
      characterId: character.id,
    ).addAll(selected, now: time);
    return selected;
  }

  String _buildPrompt({
    required CharacterSettings settings,
    required List<ChatMessage> messages,
    required List<MemoryItem> memories,
    required List<LifeMomentCandidate> lifeMoments,
    required List<AiCharacter> otherCharacters,
    required String relationshipPrompt,
    required List<WorldEvent> worldEvents,
    required List<LifeDecision> decisionHistory,
    required List<WorldResource> worldResources,
    required DateTime now,
    required int maxDecisions,
    required String relationshipOpportunityPrompt,
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
    final selectedMoments = lifeMoments.take(10).toList();
    final selectedHistory = decisionHistory.take(8).toList();

    final worldText = worldEvents.isEmpty
        ? '无。'
        : worldEvents
              .map((event) {
                final location = event.locationName?.trim();
                final locationText = location == null || location.isEmpty
                    ? ''
                    : '；地点：$location';
                final timing = event.isActiveAt(now)
                    ? '当前有效'
                    : '未来 ${event.startAt.toIso8601String()} 开始';
                final confidence = (event.normalizedConfidence * 100).round();
                return '- ID=${event.id}；状态=$timing；类型=${event.type.name}；'
                    '依据=${event.evidence.name}；可信度=$confidence%；'
                    '${event.title}$locationText；${event.description}';
              })
              .join('\n');
    final resourceText = worldResources.isEmpty
        ? '无。'
        : worldResources
              .map((item) {
                final location = item.locationName == null
                    ? ''
                    : '；地点：${item.locationName}';
                return '- ID=${item.id}；${item.name}$location；可用数量=${item.availableAt(now)}';
              })
              .join('\n');
    final memoryText = selectedMemories.isEmpty
        ? '无。'
        : selectedMemories
              .map((item) => '- ${_truncate(item.content, 140)}')
              .join('\n');
    final lifeText = selectedMoments.isEmpty
        ? '无。'
        : selectedMoments
              .map((item) {
                return '- ${item.occurredAt.month}/${item.occurredAt.day}：'
                    '${_truncate(item.event, 100)}';
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
    final decisionHistoryText = selectedHistory.isEmpty
        ? '无。'
        : selectedHistory
              .map((item) {
                final hour = item.scheduledAt.hour.toString().padLeft(2, '0');
                final minute = item.scheduledAt.minute.toString().padLeft(
                  2,
                  '0',
                );
                return '- ${item.decidedAt.month}/${item.decidedAt.day} '
                    '$hour:$minute：[${item.status.label}] '
                    '${_truncate(item.summary, 100)}；'
                    '原因：${_truncate(item.reason, 120)}'
                    '${item.statusReason.isEmpty ? '' : '；状态说明：${_truncate(item.statusReason, 80)}'}';
              })
              .join('\n');
    final characterText = otherCharacters.isEmpty
        ? '无。'
        : otherCharacters
              .map((item) {
                final relationship = item.relationship.trim().isEmpty
                    ? '关系未填写'
                    : item.relationship.trim();
                return '- ${item.displayName}（本名：${item.characterName}，$relationship）';
              })
              .join('\n');

    return '''
你是 PeiLink 的 Life Decision Engine。
你不负责写故事，不负责写 Echo，也不负责补充气氛和画面。
你的唯一任务是：根据真实世界状态、角色自身规律和已经发生过的生活，判断接下来“应该发生什么”。

【当前时间】
${now.toIso8601String()}

【当前及未来 24 小时内已确认的世界状态】
$worldText

【当前可共享且数量有限的世界资源】
$resourceText

【过去已经发生的生活】
$lifeText

【近期已经做出的生活决定】
$decisionHistoryText

【长期记忆】
$memoryText

【近期聊天，只能作为弱影响】
$chatText

【PeiLink 中存在的其他角色】
$characterText

$relationshipOpportunityPrompt

【决策规则】
1. 先问“现实生活为什么会这样发生”，再作决定。
2. 决定必须能从时间、世界状态、角色规律、未完成事项或过去生活中找到原因。
3. 不得自行创造未记录的天气、店铺、NPC、新闻、节日、地图变化或公共事件。
4. 世界状态存在依据等级：confirmed（已确认）> forecast（预测）> reported（转述）> inferred（推断）。可信度越低，只能作为越弱的影响。
5. 标记为“未来”的世界状态只能影响它开始之后的决定，不能当成现在已经发生。
6. 不要为了凑数量强行安排生活。没有足够依据时，decisions 可以为空数组。
7. 这里输出的是确定发生的事项，不是“也许”“可能”“候选”。
8. summary 只写事件骨架，例如“因为下雨取消散步，改为在家整理书架”。不要写文学化细节。
9. reason 必须明确写出因果，不允许只写“符合角色性格”。
10. scheduledAt 必须是当前时间之后、未来 24 小时内的 ISO 8601 时间。
11. worldEventIds 只能填写上面真实存在的世界状态 ID；没有直接依据时可以为空。
12. relatedCharacterNames 最多一个。需要其他角色参与时，必须同时填写有效的 relationshipOpportunityId，并且角色必须与该机会对应；否则两者都留空。
13. 普通的一天可以只有一件事，甚至没有新决定。
14. 低于 60% 可信度的状态不能单独决定重大行动，必须有角色规律、时间或其他高可信状态共同支撑。
15. reason 中要说明使用了哪些高可信依据；若使用预测、转述或推断，必须明确它只是辅助原因。
16. 优先延续近期未完成或被环境打断的决定，避免每天重新开一张空白日程。
17. 不要重复安排近期决策历史里已经存在、时间相近且内容相同的事项。
18. 只有确实需要占用上面资源时才填写 resourceClaims，key 必须是资源 ID，value 是正整数数量。
19. 同一资源不足时不要强行安排，改做其他合理决定或不输出。
20. 多角色共同出现时，不得把决定建立在争宠、排他占有、逼用户选择或无依据的角色冲突上。
21. 最多输出 $maxDecisions 条，并按发生时间排序。

只返回以下 JSON，不要 Markdown：
{
  "decisions": [
    {
      "summary": "确定发生的事情骨架",
      "reason": "为什么会发生，写清因果",
      "scheduledAt": "ISO 8601 时间",
      "location": "已知地点；未知可留空",
      "worldEventIds": [],
      "relatedCharacterNames": [],
      "relationshipOpportunityId": "",
      "resourceClaims": {}
    }
  ]
}
''';
  }

  Future<void> _persistDecisionCauses({
    required List<LifeDecision> decisions,
    required List<WorldEvent> worldEvents,
    required DateTime now,
  }) async {
    if (decisions.isEmpty) return;
    final worldById = {for (final event in worldEvents) event.id: event};
    final nodes = <CausalNode>[];

    for (final decision in decisions) {
      final parentIds = <String>[];
      for (final worldEventId in decision.worldEventIds) {
        final world = worldById[worldEventId];
        if (world == null) continue;
        final worldNodeId = 'cause_world_${world.id}';
        parentIds.add(worldNodeId);
        nodes.add(
          CausalNode(
            id: worldNodeId,
            type: CausalNodeType.worldEvent,
            sourceId: world.id,
            title: world.title,
            detail: world.description,
            occurredAt: world.startAt,
            createdAt: now,
            metadata: {
              'worldType': world.type.name,
              'evidence': world.evidence.name,
              'confidence': world.normalizedConfidence,
            },
          ),
        );
      }

      nodes.add(
        CausalNode(
          id: decision.causeNodeId,
          type: CausalNodeType.decision,
          sourceId: decision.id,
          title: decision.summary,
          detail: decision.reason,
          occurredAt: decision.scheduledAt,
          createdAt: decision.decidedAt,
          parentIds: parentIds,
          characterId: decision.characterId,
          metadata: {
            'location': decision.location,
            'relatedCharacterNames': decision.relatedCharacterNames,
            'relationshipOpportunityId': decision.relationshipOpportunityId,
            'resourceClaims': decision.resourceClaims,
          },
        ),
      );
    }

    await _causalGraph.upsertAll(nodes, now: now);
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
    return decodeStructuredModelJson(value, stage: 'Life Decision Engine');
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
