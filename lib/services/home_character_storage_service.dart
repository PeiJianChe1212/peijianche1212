import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

import '../models/ai_character.dart';
import 'character_registry_service.dart';

class HomeCharacterStorageService {
  static const String _fileName = 'home_display_character.json';

  final CharacterRegistryService _registry = CharacterRegistryService();

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<String> loadCharacterId() async {
    final characters = await _registry.loadCharacters();
    final file = await _file();
    if (!await file.exists()) {
      final activeId = await _registry.loadActiveCharacterId();
      await saveCharacterId(activeId);
      return activeId;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      final savedId = decoded is Map
          ? decoded['characterId']?.toString().trim() ?? ''
          : '';
      if (characters.any((character) => character.id == savedId)) {
        return savedId;
      }
    } catch (_) {
      // 读取失败时回到默认角色，避免首页打不开。
    }

    await saveCharacterId(AiCharacter.defaultCharacterId);
    return AiCharacter.defaultCharacterId;
  }

  Future<AiCharacter> loadCharacter() async {
    final characters = await _registry.loadCharacters();
    final selectedId = await loadCharacterId();
    return characters.firstWhere(
      (character) => character.id == selectedId,
      orElse: AiCharacter.placeholder,
    );
  }

  Future<void> saveCharacterId(String characterId) async {
    final characters = await _registry.loadCharacters();
    if (!characters.any((character) => character.id == characterId)) {
      throw StateError('首页展示角色不存在：$characterId');
    }
    final file = await _file();
    await file.writeAsString(
      jsonEncode({'characterId': characterId}),
      flush: true,
    );
  }
}
