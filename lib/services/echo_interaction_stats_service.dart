import 'dart:convert';

import '../models/echo_interaction_stats.dart';
import '../models/echo_item.dart';
import 'character_scope_service.dart';

class EchoInteractionStatsService {
  EchoInteractionStatsService({required String ownerId})
    : _scope = CharacterScopeService(ownerId);

  static const _fileName = 'echo_interaction_stats.json';
  final CharacterScopeService _scope;

  Future<Map<String, EchoInteractionStats>> loadOrCreate(
    List<EchoItem> items, {
    required bool hasRelationship,
  }) async {
    final file = await _scope.dataFile(_fileName);
    final saved = <String, EchoInteractionStats>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          for (final raw in decoded.whereType<Map>()) {
            final stats = EchoInteractionStats.fromJson(raw);
            if (stats.echoId.isNotEmpty) saved[stats.echoId] = stats;
          }
        }
      } catch (_) {}
    }

    var changed = false;
    for (final item in items) {
      if (saved.containsKey(item.id)) continue;
      saved[item.id] = _generate(item, hasRelationship: hasRelationship);
      changed = true;
    }
    if (changed) {
      await file.writeAsString(
        jsonEncode(saved.values.map((item) => item.toJson()).toList()),
        flush: true,
      );
    }
    return saved;
  }

  Future<EchoInteractionStats> createForEcho(
    EchoItem item, {
    required int commentCount,
    required bool hasRelationship,
  }) async {
    final all = await loadOrCreate([item], hasRelationship: hasRelationship);
    final generated =
        all[item.id] ?? _generate(item, hasRelationship: hasRelationship);
    final updated = EchoInteractionStats(
      echoId: generated.echoId,
      viewCount: generated.viewCount,
      likeCount: generated.likeCount,
      commentCount: commentCount,
      collectCount: generated.collectCount,
      heatLevel: generated.heatLevel,
      realLikeCount: generated.realLikeCount,
      virtualLikeCount: generated.virtualLikeCount,
    );
    all[item.id] = updated;
    final file = await _scope.dataFile(_fileName);
    await file.writeAsString(
      jsonEncode(all.values.map((value) => value.toJson()).toList()),
      flush: true,
    );
    return updated;
  }

  EchoInteractionStats _generate(
    EchoItem item, {
    required bool hasRelationship,
  }) {
    final seed = _stableHash('${item.id}|${item.createdAt.toIso8601String()}');
    final important = item.sourceSharedExperienceId.trim().isNotEmpty;
    final special = !important && item.sourceLifeEventId.trim().isNotEmpty;
    final imageBoost = item.imagePaths.isNotEmpty ? 25 : 0;
    final relationBoost = hasRelationship ? 15 : 0;
    final views = important
        ? 1000 + (seed % 1401)
        : special
        ? 300 + (seed % 701)
        : (50 + (seed % 251) + imageBoost + relationBoost).clamp(50, 300);
    final likes = important
        ? 150 + (seed % 251)
        : special
        ? 30 + (seed % 121)
        : 5 + (seed % 36);
    final collects = important
        ? 35 + (seed % 66)
        : special
        ? 10 + (seed % 31)
        : 1 + (seed % 12);
    return EchoInteractionStats(
      echoId: item.id,
      viewCount: views,
      likeCount: likes,
      commentCount: 0,
      collectCount: collects,
      heatLevel: important
          ? EchoHeatLevel.commemorative
          : (special || views >= 240)
          ? EchoHeatLevel.popular
          : EchoHeatLevel.calm,
    );
  }

  int _stableHash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = ((hash * 37) + unit) & 0x7fffffff;
    }
    return hash;
  }
}
