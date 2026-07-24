import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/ai_character.dart';

class CharacterRegistryService {
  static const String _registryFileName = 'character_registry.json';
  static const String _activeFileName = 'active_character.json';

  Future<Directory> _documentsDirectory() => getApplicationDocumentsDirectory();

  Future<File> _registryFile() async {
    final directory = await _documentsDirectory();
    return File('${directory.path}/$_registryFileName');
  }

  Future<File> _activeFile() async {
    final directory = await _documentsDirectory();
    return File('${directory.path}/$_activeFileName');
  }

  Future<List<AiCharacter>> loadCharacters() async {
    final file = await _registryFile();
    if (!await file.exists()) return _createInitialRegistry();

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return _createInitialRegistry();

      final characters = decoded
          .whereType<Map>()
          .map(AiCharacter.fromJson)
          .where((character) => character.id.trim().isNotEmpty)
          .toList();

      if (characters.isEmpty) return _createInitialRegistry();
      if (!characters.any(
        (character) => character.id == AiCharacter.defaultCharacterId,
      )) {
        characters.insert(0, AiCharacter.peiJianChe());
        await saveCharacters(characters);
      }
      return characters;
    } catch (_) {
      return _createInitialRegistry();
    }
  }

  Future<List<AiCharacter>> _createInitialRegistry() async {
    final characters = <AiCharacter>[AiCharacter.peiJianChe()];
    await saveCharacters(characters);
    await setActiveCharacter(AiCharacter.defaultCharacterId);
    return characters;
  }

  Future<void> saveCharacters(List<AiCharacter> characters) async {
    final file = await _registryFile();
    await file.writeAsString(
      jsonEncode(characters.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> addCharacter(AiCharacter character) async {
    final characters = await loadCharacters();
    final index = characters.indexWhere((item) => item.id == character.id);
    if (index >= 0) {
      characters[index] = character;
    } else {
      characters.add(character);
    }
    await saveCharacters(characters);
  }

  Future<void> updateCharacter(AiCharacter character) => addCharacter(character);

  Future<void> deleteCharacter(String characterId) async {
    if (characterId == AiCharacter.defaultCharacterId) {
      throw StateError('内置角色裴简澈不能在当前版本删除。');
    }

    final characters = await loadCharacters();
    characters.removeWhere((item) => item.id == characterId);
    await saveCharacters(characters);

    final activeId = await loadActiveCharacterId();
    if (activeId == characterId) {
      await setActiveCharacter(AiCharacter.defaultCharacterId);
    }
  }

  Future<String> loadActiveCharacterId() async {
    final file = await _activeFile();
    if (!await file.exists()) {
      await setActiveCharacter(AiCharacter.defaultCharacterId);
      return AiCharacter.defaultCharacterId;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      final id = decoded is Map ? decoded['characterId']?.toString() : null;
      if (id == null || id.trim().isEmpty) {
        return AiCharacter.defaultCharacterId;
      }
      final characters = await loadCharacters();
      return characters.any((item) => item.id == id)
          ? id
          : AiCharacter.defaultCharacterId;
    } catch (_) {
      return AiCharacter.defaultCharacterId;
    }
  }

  Future<AiCharacter> loadActiveCharacter() async {
    final characters = await loadCharacters();
    final activeId = await loadActiveCharacterId();
    return characters.firstWhere(
      (item) => item.id == activeId,
      orElse: AiCharacter.peiJianChe,
    );
  }

  Future<void> setActiveCharacter(String characterId) async {
    final characters = await loadCharacters();
    if (!characters.any((item) => item.id == characterId)) {
      throw StateError('要切换的角色不存在：$characterId');
    }
    final file = await _activeFile();
    await file.writeAsString(
      jsonEncode({'characterId': characterId}),
      flush: true,
    );
  }
}
