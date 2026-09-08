import 'package:flutter/foundation.dart';

import '../models/ai_character.dart';
import 'auto_memory_extraction_service.dart';
import 'character_registry_service.dart';
import 'character_scope_service.dart';
import 'memory2_mutation_coordinator.dart';
import 'relationship_memory_storage_service.dart';
import 'shared_experience_storage_service.dart';

/// The existing explicit character deletion, including global relationship rows.
class CharacterDeletionService {
  CharacterDeletionService({CharacterRegistryService? registry})
    : registry = registry ?? CharacterRegistryService();

  final CharacterRegistryService registry;

  Future<void> delete(String characterId) async {
    if (characterId == AiCharacter.defaultCharacterId ||
        characterId.trim().isEmpty) {
      throw StateError('不能删除默认角色或空角色。');
    }
    if (kIsWeb) {
      await registry.deleteCharacter(characterId);
      await CharacterScopeService(characterId).deleteAllData();
      return;
    }
    await AutoMemoryExtractionService.duringCharacterDeletion(
      characterId,
      () => _deleteBlocked(characterId),
    );
  }

  Future<void> _deleteBlocked(String characterId) async {
    final characters = await registry.loadAllCharactersStrict();
    final originals = characters.where((item) => item.id == characterId);
    if (originals.isEmpty) throw StateError('角色不存在，请刷新后重试。');
    final original = originals.single;
    final shared = SharedExperienceStorageService();
    final relationships = RelationshipMemoryStorageService();
    // Validate all global inputs before any destructive operation.
    await shared.validateForRemoval();
    await relationships.validateForRemoval();
    await Memory2MutationCoordinator.runExclusive(characterId, () async {
      // Registry failure must leave both private and global data untouched.
      await registry.deleteCharacter(characterId);
      try {
        await shared.removeForCharacter(characterId);
        await relationships.removeForCharacter(characterId);
        await CharacterScopeService(characterId).deleteAllData();
      } catch (_) {
        // Keep the character reachable so a failed directory cleanup can retry.
        await registry.addCharacter(original);
        rethrow;
      }
    });
  }
}
