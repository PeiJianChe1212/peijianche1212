import '../models/causal_node.dart';
import '../models/world_event.dart';
import 'causal_graph_service.dart';
import 'world_timeline_service.dart';

class WorldSimulationReport {
  const WorldSimulationReport({
    this.sourcesEvaluated = 0,
    this.effectsCreated = 0,
    this.effectsRefreshed = 0,
    this.effectsEnded = 0,
    this.statesEnded = 0,
    this.rulesSkipped = 0,
  });

  final int sourcesEvaluated;
  final int effectsCreated;
  final int effectsRefreshed;
  final int effectsEnded;
  final int statesEnded;
  final int rulesSkipped;

  bool get changed =>
      effectsCreated > 0 ||
      effectsRefreshed > 0 ||
      effectsEnded > 0 ||
      statesEnded > 0;
}

/// 按已经写入 World Timeline 的确定性规则推进世界。
///
/// 这一层不调用模型，也不随机创造天气、店铺、NPC 或公共事件。
/// 世界事件只有显式携带 metadata.effects 等规则时，才会产生后续状态。
class WorldSimulationService {
  WorldSimulationService({
    WorldTimelineService? timeline,
    CausalGraphService? causalGraph,
  })  : _timeline = timeline ?? WorldTimelineService(),
        _causalGraph = causalGraph ?? CausalGraphService();

  final WorldTimelineService _timeline;
  final CausalGraphService _causalGraph;

  Future<WorldSimulationReport> advance({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final before = await _timeline.loadAll(now: time);
    final beforeById = {for (final event in before) event.id: event};
    final active = before.where((event) => event.isActiveAt(time)).toList();
    final activeStateKeys = active
        .map((event) => event.stateKey)
        .whereType<String>()
        .where((key) => key.isNotEmpty)
        .toSet();

    var created = 0;
    var refreshed = 0;
    var ended = 0;
    var statesEnded = 0;
    var skipped = 0;

    for (final source in active) {
      if (!_requirementsMet(source, activeStateKeys)) {
        skipped += _readEffects(source).length;
        continue;
      }

      final endedKeys = _readStringList(source.metadata['endsStateKeys']);
      for (final key in endedKeys) {
        final count = await _timeline.endActiveState(
          key,
          now: time,
          exceptEventId: source.id,
        );
        statesEnded += count;
      }

      final effects = _readEffects(source);
      for (var index = 0; index < effects.length; index++) {
        final effect = effects[index];
        final derived = _buildEffect(
          source: source,
          effect: effect,
          index: index,
          now: time,
        );
        if (derived == null) {
          skipped++;
          continue;
        }

        final existed = beforeById.containsKey(derived.id);
        final stateKey = derived.stateKey;
        if (stateKey == null) {
          await _timeline.upsert(derived, now: time);
        } else {
          await _timeline.upsertState(
            derived,
            stateKey: stateKey,
            now: time,
          );
        }
        await _writeCausalNodes(source, derived, now: time);

        if (existed) {
          refreshed++;
        } else {
          created++;
        }
      }
    }

    final afterSources = await _timeline.loadAll(now: time);
    final activeSourceIds = afterSources
        .where((event) => event.isActiveAt(time))
        .map((event) => event.id)
        .toSet();

    for (final event in afterSources) {
      final sourceId = _readText(event.metadata['simulationSourceId']);
      if (sourceId.isEmpty || activeSourceIds.contains(sourceId)) continue;
      if (event.statusAt(time) == WorldEventStatus.ended) continue;
      await _timeline.endEvent(event.id, now: time);
      ended++;
    }

    return WorldSimulationReport(
      sourcesEvaluated: active.length,
      effectsCreated: created,
      effectsRefreshed: refreshed,
      effectsEnded: ended,
      statesEnded: statesEnded,
      rulesSkipped: skipped,
    );
  }

  bool _requirementsMet(WorldEvent source, Set<String> activeStateKeys) {
    final required = _readStringList(
      source.metadata['requiresActiveStateKeys'],
    );
    if (required.any((key) => !activeStateKeys.contains(key))) return false;

    final blocked = _readStringList(
      source.metadata['blockedByActiveStateKeys'],
    );
    if (blocked.any(activeStateKeys.contains)) return false;
    return true;
  }

  List<Map<String, dynamic>> _readEffects(WorldEvent source) {
    final raw = source.metadata['effects'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  WorldEvent? _buildEffect({
    required WorldEvent source,
    required Map<String, dynamic> effect,
    required int index,
    required DateTime now,
  }) {
    final title = _readText(effect['title']);
    if (title.isEmpty) return null;

    final suffix = _safeId(
      _readText(effect['idSuffix']).isEmpty
          ? '${_readType(effect['type']).name}_$index'
          : _readText(effect['idSuffix']),
    );
    final startOffset = _readInt(effect['startOffsetMinutes']);
    final endOffset = _readNullableInt(effect['endOffsetMinutes']);
    final startAt = source.startAt.add(Duration(minutes: startOffset));
    final endAt = endOffset == null
        ? source.endAt
        : source.startAt.add(Duration(minutes: endOffset));
    final confidenceMultiplier = _readDouble(
      effect['confidenceMultiplier'],
      fallback: 1.0,
    ).clamp(0.0, 1.0).toDouble();
    final stateKey = _readText(effect['stateKey']);
    final extraMetadata = effect['metadata'] is Map
        ? Map<String, dynamic>.from(effect['metadata'] as Map)
        : const <String, dynamic>{};
    final derivedId = 'sim_${_safeId(source.id)}_$suffix';
    final causeNodeId = 'cause_world_$derivedId';

    return WorldEvent(
      id: derivedId,
      type: _readType(effect['type']),
      title: title,
      description: _readText(effect['description']),
      startAt: startAt,
      endAt: endAt,
      createdAt: now,
      status: now.isBefore(startAt)
          ? WorldEventStatus.scheduled
          : WorldEventStatus.active,
      locationId: _nullableText(effect['locationId']) ?? source.locationId,
      locationName:
          _nullableText(effect['locationName']) ?? source.locationName,
      participantCharacterIds: _readStringList(
        effect['participantCharacterIds'],
      ).isEmpty
          ? source.participantCharacterIds
          : _readStringList(effect['participantCharacterIds']),
      tags: {
        ...source.tags,
        ..._readStringList(effect['tags']),
        'simulated_effect',
      }.toList(),
      source: 'world_simulation',
      evidence: source.evidence,
      confidence:
          source.normalizedConfidence * confidenceMultiplier,
      metadata: {
        ...extraMetadata,
        if (stateKey.isNotEmpty) 'stateKey': stateKey,
        'simulationSourceId': source.id,
        'simulationRuleIndex': index,
        'causeNodeId': causeNodeId,
      },
    );
  }

  Future<void> _writeCausalNodes(
    WorldEvent source,
    WorldEvent derived, {
    required DateTime now,
  }) async {
    final sourceNodeId = 'cause_world_${_safeId(source.id)}';
    final derivedNodeId = 'cause_world_${_safeId(derived.id)}';
    await _causalGraph.upsertAll(
      [
        CausalNode(
          id: sourceNodeId,
          type: CausalNodeType.worldEvent,
          sourceId: source.id,
          title: source.title,
          detail: source.description,
          occurredAt: source.startAt,
          createdAt: now,
          metadata: {
            'worldEventType': source.type.name,
            'stateKey': source.stateKey,
          },
        ),
        CausalNode(
          id: derivedNodeId,
          type: CausalNodeType.worldEvent,
          sourceId: derived.id,
          title: derived.title,
          detail: derived.description,
          occurredAt: derived.startAt,
          createdAt: now,
          parentIds: [sourceNodeId],
          metadata: {
            'worldEventType': derived.type.name,
            'stateKey': derived.stateKey,
            'simulationSourceId': source.id,
          },
        ),
      ],
      now: now,
    );
  }

  WorldEventType _readType(dynamic value) {
    final name = _readText(value);
    return WorldEventType.values.firstWhere(
      (item) => item.name == name,
      orElse: () => WorldEventType.other,
    );
  }

  List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map(_readText)
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  String _readText(dynamic value) => value?.toString().trim() ?? '';

  String? _nullableText(dynamic value) {
    final text = _readText(value);
    return text.isEmpty ? null : text;
  }

  int _readInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(_readText(value)) ?? 0;
  }

  int? _readNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    final text = _readText(value);
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  double _readDouble(dynamic value, {required double fallback}) {
    if (value is num) return value.toDouble();
    return double.tryParse(_readText(value)) ?? fallback;
  }

  String _safeId(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return cleaned.isEmpty ? 'event' : cleaned;
  }
}
