import 'dart:convert';

import '../models/cooldown_state.dart';
import 'character_scope_service.dart';

class RelationshipCooldownService {
  RelationshipCooldownService({this.characterId});

  final String? characterId;

  Future<CooldownState> loadState() async {
    final file = await CharacterScopeService(
      characterId,
    ).dataFile('relationship_cooldown.json');
    if (!await file.exists()) return const CooldownState.normal();

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const CooldownState.normal();
      return CooldownState.fromJson(decoded);
    } catch (_) {
      return const CooldownState.normal();
    }
  }

  Future<CooldownState> enterCooldown(
    Duration duration, {
    String? reason,
    DateTime? now,
  }) async {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Cooldown duration must be greater than zero.',
      );
    }

    final startTime = now ?? DateTime.now();
    final normalizedReason = reason?.trim();
    final state = CooldownState(
      state: ChatRelationshipState.cooldown,
      startTime: startTime,
      endTime: startTime.add(duration),
      reason: normalizedReason == null || normalizedReason.isEmpty
          ? null
          : normalizedReason,
    );
    await _saveState(state);
    return state;
  }

  Future<void> clearCooldown() async {
    await _saveState(const CooldownState.normal());
  }

  Future<bool> isInCooldown({DateTime? now}) async {
    final state = await loadState();
    return state.isInCooldownAt(now ?? DateTime.now());
  }

  Future<void> _saveState(CooldownState state) async {
    final file = await CharacterScopeService(
      characterId,
    ).dataFile('relationship_cooldown.json');
    await file.writeAsString(jsonEncode(state.toJson()), flush: true);
  }
}
