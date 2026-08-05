import 'dart:convert';

import '../models/ai_character.dart';
import '../models/character_profile.dart';
import '../models/character_settings.dart';
import 'character_scope_service.dart';

class CharacterProfileStorageService {
  const CharacterProfileStorageService({required this.characterId});
  final String characterId;

  Future<CharacterProfile> load({
    required AiCharacter character,
    required CharacterSettings legacySettings,
  }) async {
    final fallback = CharacterProfile.fromLegacy(character, legacySettings);
    try {
      final file = await CharacterScopeService(
        characterId,
      ).dataFile('character_profile.json');
      if (!await file.exists()) return fallback;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map
          ? CharacterProfile.fromJson(decoded, characterId)
          : fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> save(CharacterProfile profile) async {
    final file = await CharacterScopeService(
      characterId,
    ).dataFile('character_profile.json');
    await file.writeAsString(jsonEncode(profile.toJson()), flush: true);
  }
}
