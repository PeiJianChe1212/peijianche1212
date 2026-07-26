import '../models/life_decision.dart';
import '../models/life_moment.dart';

/// Life Engine 输出的最后一道确定性渲染层。
///
/// 模型只负责 event/detail/feeling/shareHook 等表达草稿；所有已经由
/// Decision Engine 决定的事实，都由这里重新写回，避免生成模型篡改时间、
/// 地点、因果、世界依据或资源占用。
class LifeEventRendererService {
  const LifeEventRendererService();

  List<LifeMomentCandidate> render({
    required List<dynamic> rawItems,
    required List<LifeDecision> decisions,
    DateTime? now,
  }) {
    if (rawItems.isEmpty || decisions.isEmpty) return const [];

    final renderedAt = now ?? DateTime.now();
    final decisionsById = <String, LifeDecision>{
      for (final decision in decisions) decision.id: decision,
    };
    final consumedDecisionIds = <String>{};
    final events = <LifeMomentCandidate>[];

    for (var index = 0; index < rawItems.length; index++) {
      final raw = rawItems[index];
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final decisionId = _text(map['decisionId']);
      final decision = decisionsById[decisionId];

      // 一条决定最多只能落实为一条生活，模型重复输出时以后者无效处理。
      if (decision == null || !consumedDecisionIds.add(decisionId)) continue;

      final eventText = _text(map['event']);
      final detailText = _text(map['detail']);
      if (eventText.isEmpty || detailText.isEmpty) continue;

      final eventId = 'life_${renderedAt.microsecondsSinceEpoch}_$index';
      events.add(
        LifeMomentCandidate(
          id: eventId,
          scene: _safeScene(
            generated: _text(map['scene']),
            decidedLocation: decision.location,
          ),
          event: eventText,
          detail: detailText,
          feeling: _text(map['feeling']),
          shareHook: _text(map['shareHook']),
          occurredAt: decision.scheduledAt,
          decisionId: decision.id,
          causeNodeId: 'cause_life_$eventId',
          relatedCharacterNames: decision.relatedCharacterNames,
          decisionSummary: decision.summary,
          decisionReason: decision.reason,
          worldEventIds: decision.worldEventIds,
          resourceClaims: decision.resourceClaims,
          renderedAt: renderedAt,
          rendererVersion: 1,
          relationshipOpportunityId:
              decision.relationshipOpportunityId,
        ),
      );
    }

    events.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    return events;
  }

  String _safeScene({
    required String generated,
    required String decidedLocation,
  }) {
    final location = decidedLocation.trim();
    if (location.isNotEmpty) return location;
    final scene = generated.trim();
    if (scene.isEmpty) return '日常生活中';
    return scene;
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';
}
