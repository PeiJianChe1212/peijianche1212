import '../models/ai_character.dart';
import '../models/character_relationship.dart';
import '../models/relationship_network.dart';
import '../models/relationship_opportunity.dart';
import '../models/world_event.dart';
import 'relationship_network_service.dart';
import 'echo_comment_interaction_storage_service.dart';
import 'relationship_opportunity_state_service.dart';

/// 决定“此刻是否适合让两个角色自然产生共同生活”的调度层。
///
/// 它不生成剧情，只提供经过关系阶段、近期互动和世界事实筛选后的机会。
/// Life Decision Engine 只能从这些机会中选择相关角色。
class RelationshipOpportunityEngineService {
  RelationshipOpportunityEngineService({
    RelationshipNetworkService? networkService,
    RelationshipOpportunityStateService? stateService,
  })  : _networkService = networkService ?? RelationshipNetworkService(),
        _stateService =
            stateService ?? RelationshipOpportunityStateService();

  final RelationshipNetworkService _networkService;
  final RelationshipOpportunityStateService _stateService;
  final EchoCommentInteractionStorageService _echoInteractionStorage =
      EchoCommentInteractionStorageService();

  Future<List<RelationshipOpportunity>> evaluate({
    required AiCharacter currentCharacter,
    required List<AiCharacter> allCharacters,
    required List<WorldEvent> worldEvents,
    DateTime? now,
    int limit = 3,
  }) async {
    final time = now ?? DateTime.now();
    final others = allCharacters
        .where((item) => item.id != currentCharacter.id)
        .toList();
    if (others.isEmpty) return const [];

    final snapshot = await _networkService.buildSnapshot(
      characters: allCharacters,
    );
    final lastSelected = await _stateService.loadLastSelectedAt();
    final opportunities = <RelationshipOpportunity>[];

    for (final other in others) {
      final edge = snapshot.edgeFor(currentCharacter.id, other.id);
      if (edge == null) continue;
      final previousSelection = lastSelected[edge.id];
      final score = _score(edge, previousSelection, time);
      if (score < 35) continue;

      final worldMatch = _pickWorldEvent(worldEvents, time);
      final type = _pickType(edge, worldMatch);
      opportunities.add(
        RelationshipOpportunity(
          id: 'opportunity_${edge.id}_${time.year}${time.month}${time.day}',
          currentCharacterId: currentCharacter.id,
          otherCharacterId: other.id,
          otherCharacterName: other.displayName,
          type: type,
          reason: _reason(edge, previousSelection, time, worldMatch),
          score: score,
          createdAt: time,
          expiresAt: time.add(const Duration(hours: 24)),
          suggestedActivity: _suggestedActivity(type, worldMatch),
          suggestedLocation: worldMatch?.locationName?.trim() ?? '',
          worldEventIds: worldMatch == null ? const [] : [worldMatch.id],
        ),
      );
    }

    final echoCandidates =
        await _echoInteractionStorage.loadCandidates(now: time);
    for (final candidate in echoCandidates) {
      final other = others.where(
        (item) => candidate.isForPair(currentCharacter.id, item.id),
      );
      if (other.isEmpty) continue;
      final matched = other.first;
      final duplicate = opportunities.any(
        (item) => item.otherCharacterId == matched.id &&
            item.suggestedActivity == candidate.suggestedActivity,
      );
      if (duplicate) continue;
      opportunities.add(
        RelationshipOpportunity(
          id: candidate.id,
          currentCharacterId: currentCharacter.id,
          otherCharacterId: matched.id,
          otherCharacterName: matched.displayName,
          type: RelationshipOpportunityType.sharedRoutine,
          reason: '${candidate.reason}；该意向只是候选，仍需结合当前生活决定是否发生',
          score: 64,
          createdAt: candidate.createdAt,
          expiresAt: candidate.expiresAt,
          suggestedActivity: candidate.suggestedActivity,
        ),
      );
    }

    opportunities.sort((a, b) => b.score.compareTo(a.score));
    return opportunities.take(limit.clamp(1, 5).toInt()).toList();
  }

  String buildPromptSection(List<RelationshipOpportunity> opportunities) {
    if (opportunities.isEmpty) {
      return '''
【关系机会引擎】
当前没有适合安排其他角色参与的自然机会。
本轮所有决定的 relationshipOpportunityId 必须为空，relatedCharacterNames 必须为空。
''';
    }

    final lines = opportunities.map((item) {
      final location = item.suggestedLocation.isEmpty
          ? '不限定地点'
          : item.suggestedLocation;
      final worldIds = item.worldEventIds.isEmpty
          ? '无'
          : item.worldEventIds.join('、');
      return '''
- opportunityId：${item.id}
  可参与角色：${item.otherCharacterName}
  类型：${item.type.label}
  机会依据：${item.reason}
  建议方向：${item.suggestedActivity}
  建议地点：$location
  可引用世界事件 ID：$worldIds
''';
    }).join('\n');

    return '''
【Relationship Opportunity Engine｜允许使用的关系机会】
$lines

使用规则：
1. 关系机会只是“可以自然发生”，不是强制每轮安排多人事件。
2. 需要其他角色参与时，必须选择上方一个 opportunityId，并使用其对应角色。
3. 不得把一个机会改成恋爱竞争、争宠、修罗场或无依据的旧交情。
4. 没有合适机会时宁可生成单人生活，不要为了热闹硬塞角色。
5. 同一条决定最多使用一个关系机会。
''';
  }

  RelationshipOpportunity? validateSelection({
    required String opportunityId,
    required Iterable<String> requestedNames,
    required List<RelationshipOpportunity> opportunities,
  }) {
    final id = opportunityId.trim();
    if (id.isEmpty) return null;
    RelationshipOpportunity? selected;
    for (final item in opportunities) {
      if (item.id == id) {
        selected = item;
        break;
      }
    }
    if (selected == null) return null;

    final names = requestedNames.map((item) => item.trim()).toSet();
    if (!names.contains(selected.otherCharacterName)) return null;
    return selected;
  }

  Future<void> markSelected(RelationshipOpportunity opportunity, {
    DateTime? now,
  }) {
    final relationshipId = CharacterRelationship.buildId(
      opportunity.currentCharacterId,
      opportunity.otherCharacterId,
    );
    return _stateService.markSelected(relationshipId, now: now);
  }

  int _score(
    RelationshipNetworkEdge edge,
    DateTime? lastSelectedAt,
    DateTime now,
  ) {
    var score = switch (edge.stage) {
      CharacterRelationshipStage.aware => 42,
      CharacterRelationshipStage.acquainted => 52,
      CharacterRelationshipStage.familiar => 62,
      CharacterRelationshipStage.cooperative => 68,
      CharacterRelationshipStage.friend => 72,
    };

    final lastInteraction = edge.lastInteractionAt;
    if (lastInteraction == null) {
      score += 8;
    } else {
      final gap = now.difference(lastInteraction);
      if (gap < const Duration(hours: 18)) score -= 28;
      if (gap >= const Duration(days: 3)) score += 8;
      if (gap >= const Duration(days: 7)) score += 6;
    }

    if (lastSelectedAt != null) {
      final gap = now.difference(lastSelectedAt);
      if (gap < const Duration(hours: 24)) score -= 40;
      if (gap < const Duration(days: 3)) score -= 12;
    }

    score += (edge.cooperation ~/ 20).clamp(0, 5).toInt();
    score += (edge.ease ~/ 25).clamp(0, 4).toInt();
    return score.clamp(0, 100).toInt();
  }

  WorldEvent? _pickWorldEvent(List<WorldEvent> events, DateTime now) {
    final usable = events.where((item) {
      final startsSoon = item.startAt.isBefore(now.add(const Duration(hours: 18)));
      final notEnded = item.endAt == null || item.endAt!.isAfter(now);
      return startsSoon && notEnded;
    }).toList();
    if (usable.isEmpty) return null;
    usable.sort((a, b) => b.normalizedConfidence.compareTo(a.normalizedConfidence));
    return usable.first;
  }

  RelationshipOpportunityType _pickType(
    RelationshipNetworkEdge edge,
    WorldEvent? event,
  ) {
    final eventText = event == null
        ? ''
        : '${event.title} ${event.description}'.toLowerCase();
    if (_containsAny(eventText, ['节日', '生日', '庆祝', '纪念'])) {
      return RelationshipOpportunityType.celebration;
    }
    if (_containsAny(eventText, ['排队', '交通', '停电', '维修', '搬运', '准备'])) {
      return RelationshipOpportunityType.cooperation;
    }
    return switch (edge.stage) {
      CharacterRelationshipStage.aware => RelationshipOpportunityType.encounter,
      CharacterRelationshipStage.acquainted =>
        RelationshipOpportunityType.conversation,
      CharacterRelationshipStage.familiar =>
        RelationshipOpportunityType.sharedRoutine,
      CharacterRelationshipStage.cooperative =>
        RelationshipOpportunityType.cooperation,
      CharacterRelationshipStage.friend =>
        RelationshipOpportunityType.sharedRoutine,
    };
  }

  String _reason(
    RelationshipNetworkEdge edge,
    DateTime? lastSelectedAt,
    DateTime now,
    WorldEvent? event,
  ) {
    final parts = <String>['当前关系阶段为“${edge.stage.label}”'];
    if (edge.lastInteractionAt == null) {
      parts.add('尚无共同经历，适合从低压力接触开始');
    } else {
      final days = now.difference(edge.lastInteractionAt!).inDays;
      parts.add(days <= 0 ? '今天已有互动，只有非常自然时才再次碰面' : '距离上次互动约 $days 天');
    }
    if (lastSelectedAt != null) {
      parts.add('关系机会最近已被使用过，应避免重复套路');
    }
    if (event != null) parts.add('世界中存在“${event.title}”这一可共享事实');
    return parts.join('；');
  }

  String _suggestedActivity(
    RelationshipOpportunityType type,
    WorldEvent? event,
  ) {
    if (event != null) return '围绕“${event.title}”产生自然且克制的共同片段';
    return switch (type) {
      RelationshipOpportunityType.encounter => '短暂碰面或顺手打个招呼',
      RelationshipOpportunityType.conversation => '围绕眼前小事聊几句',
      RelationshipOpportunityType.cooperation => '为一件具体小事自然分工',
      RelationshipOpportunityType.help => '在不越界的情况下顺手帮忙',
      RelationshipOpportunityType.sharedRoutine => '共享一段普通日常',
      RelationshipOpportunityType.celebration => '围绕明确节日或纪念事项共同参与',
    };
  }

  bool _containsAny(String text, List<String> values) =>
      values.any(text.contains);
}
