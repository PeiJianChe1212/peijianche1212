import '../models/ai_character.dart';
import '../models/character_profile.dart';
import '../models/peilink_character_visual_profile.dart';
import 'character_profile_storage_service.dart';
import 'character_registry_service.dart';
import 'character_settings_storage_service.dart';

class PeiLinkCharacterVisualProfileService {
  const PeiLinkCharacterVisualProfileService();

  PeiLinkCharacterVisualProfile fromProfile(CharacterProfile profile) =>
      PeiLinkCharacterVisualProfile.fromProfile(profile);

  Future<Map<String, PeiLinkCharacterVisualProfile>> loadRequired(
    Iterable<String> requiredCharacterIds,
  ) async {
    final ids = requiredCharacterIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return const {};
    final characters = await CharacterRegistryService().loadCharacters();
    final byId = {for (final character in characters) character.id: character};
    final result = <String, PeiLinkCharacterVisualProfile>{};
    for (final id in ids) {
      final character = byId[id];
      if (character == null) continue;
      final settings = await CharacterSettingsStorageService(
        characterId: id,
      ).loadSettings();
      final profile = await CharacterProfileStorageService(
        characterId: id,
      ).load(character: character, legacySettings: settings);
      result[id] = PeiLinkCharacterVisualProfile.fromProfile(profile);
    }
    return result;
  }

  Future<PeiLinkCharacterVisualProfile> loadForCharacter(
    AiCharacter character,
  ) async {
    final settings = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();
    final profile = await CharacterProfileStorageService(
      characterId: character.id,
    ).load(character: character, legacySettings: settings);
    return PeiLinkCharacterVisualProfile.fromProfile(profile);
  }
}
