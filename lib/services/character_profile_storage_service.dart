import 'dart:convert';

import '../models/ai_character.dart';
import '../models/character_profile.dart';
import '../models/character_settings.dart';
import '../platform/storage/platform_storage.dart';
import 'character_scope_service.dart';

class CharacterProfileStorageService {
  const CharacterProfileStorageService({
    required this.characterId,
    this.storage,
  });
  final String characterId;
  final PlatformStorage? storage;

  Future<CharacterProfile> load({
    required AiCharacter character,
    required CharacterSettings legacySettings,
  }) async {
    final fallback = CharacterProfile.fromLegacy(character, legacySettings);
    final scope = CharacterScopeService(characterId);
    final store = storage ?? await scope.storage();
    try {
      final key = await scope.dataKey('character_profile.json');
      if (!await store.exists(key)) return fallback;
      final decoded = jsonDecode(await store.readText(key));
      return decoded is Map
          ? CharacterProfile.fromJson(decoded, characterId)
          : fallback;
    } catch (_) {
      if (store is FailFastPlatformStorage) rethrow;
      return fallback;
    }
  }

  Future<void> save(CharacterProfile profile) async {
    final scope = CharacterScopeService(characterId);
    final store = storage ?? await scope.storage();
    final key = await scope.dataKey('character_profile.json');
    await store.writeText(key, jsonEncode(profile.toJson()));
  }
}
