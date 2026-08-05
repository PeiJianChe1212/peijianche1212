import 'dart:convert';

import '../models/character_user_profile.dart';
import 'character_scope_service.dart';

class CharacterUserProfileStorageService {
  const CharacterUserProfileStorageService({required this.characterId});

  final String characterId;

  Future<CharacterUserProfile> load() async {
    final fallback = CharacterUserProfile(characterId: characterId);
    try {
      final file = await CharacterScopeService(
        characterId,
      ).dataFile('user_persona.json');
      if (!await file.exists()) return fallback;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return fallback;
      return CharacterUserProfile.fromJson(decoded, characterId: characterId);
    } catch (_) {
      return fallback;
    }
  }

  Future<void> save(CharacterUserProfile profile) async {
    final file = await CharacterScopeService(
      characterId,
    ).dataFile('user_persona.json');
    await file.writeAsString(jsonEncode(profile.toJson()), flush: true);
  }
}
