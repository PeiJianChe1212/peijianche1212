import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

import '../models/ai_character.dart';
import '../models/character_relationship.dart';

class CharacterRelationshipStorageService {
  static const String _fileName = 'character_relationships.json';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<CharacterRelationship>> loadAll() async {
    final file = await _file();
    if (!await file.exists()) return <CharacterRelationship>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <CharacterRelationship>[];
      return decoded
          .whereType<Map>()
          .map(CharacterRelationship.fromJson)
          .where(
            (item) =>
                item.characterIdA.isNotEmpty &&
                item.characterIdB.isNotEmpty &&
                item.characterIdA != item.characterIdB,
          )
          .toList();
    } catch (_) {
      return <CharacterRelationship>[];
    }
  }

  Future<void> saveAll(List<CharacterRelationship> items) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(items.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<List<CharacterRelationship>> ensureForCharacters(
    List<AiCharacter> characters,
  ) async {
    final valid = characters
        .where((item) => item.id.trim().isNotEmpty)
        .toList();
    final items = List<CharacterRelationship>.from(await loadAll());
    var changed = false;
    final now = DateTime.now();

    for (var i = 0; i < valid.length; i++) {
      for (var j = i + 1; j < valid.length; j++) {
        final id = CharacterRelationship.buildId(valid[i].id, valid[j].id);
        if (items.any((item) => item.id == id)) continue;
        final ids = [valid[i].id, valid[j].id]..sort();
        items.add(
          CharacterRelationship(
            id: id,
            characterIdA: ids[0],
            characterIdB: ids[1],
            stage: CharacterRelationshipStage.aware,
            createdAt: now,
            updatedAt: now,
          ),
        );
        changed = true;
      }
    }

    final validIds = valid.map((item) => item.id).toSet();
    final before = items.length;
    items.removeWhere(
      (item) =>
          !validIds.contains(item.characterIdA) ||
          !validIds.contains(item.characterIdB),
    );
    changed = changed || before != items.length;

    if (changed) await saveAll(items);
    return items;
  }

  Future<CharacterRelationship?> find(String firstId, String secondId) async {
    final id = CharacterRelationship.buildId(firstId, secondId);
    final items = await loadAll();
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> save(CharacterRelationship relationship) async {
    final items = List<CharacterRelationship>.from(await loadAll());
    final index = items.indexWhere((item) => item.id == relationship.id);
    if (index >= 0) {
      items[index] = relationship;
    } else {
      items.add(relationship);
    }
    await saveAll(items);
  }

  Future<CharacterRelationship> recordSharedEvent({
    required String firstId,
    required String secondId,
    DateTime? occurredAt,
    String? note,
    int experienceWeight = 1,
  }) async {
    final now = occurredAt ?? DateTime.now();
    final existing = await find(firstId, secondId);
    final ids = [firstId, secondId]..sort();
    final base =
        existing ??
        CharacterRelationship(
          id: CharacterRelationship.buildId(firstId, secondId),
          characterIdA: ids[0],
          characterIdB: ids[1],
          stage: CharacterRelationshipStage.aware,
          createdAt: now,
          updatedAt: now,
        );
    final safeWeight = experienceWeight.clamp(1, 3).toInt();
    final count = base.sharedEventCount + safeWeight;
    final nextStage = _stageAfterSharedEvents(base.stage, count);
    final updated = base.copyWith(
      stage: nextStage,
      sharedEventCount: count,
      note: note?.trim().isNotEmpty == true ? note!.trim() : base.note,
      updatedAt: now,
      lastSharedEventAt: now,
    );
    await save(updated);
    return updated;
  }

  CharacterRelationshipStage _stageAfterSharedEvents(
    CharacterRelationshipStage current,
    int count,
  ) {
    if (current == CharacterRelationshipStage.friend) return current;
    if (count >= 8) return CharacterRelationshipStage.friend;
    if (count >= 5) return CharacterRelationshipStage.cooperative;
    if (count >= 3) return CharacterRelationshipStage.familiar;
    if (count >= 1) return CharacterRelationshipStage.acquainted;
    return current;
  }
}
