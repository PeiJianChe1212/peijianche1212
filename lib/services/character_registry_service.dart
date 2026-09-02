import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

import '../models/ai_character.dart';
import 'developer_environment_service.dart';

class CharacterRegistryService {
  static const String _registryFileName = 'character_registry.json';
  static const String _activeFileName = 'active_character.json';

  Future<Directory> _documentsDirectory() => getApplicationDocumentsDirectory();
  Future<File> _registryFile() async =>
      File('${(await _documentsDirectory()).path}/$_registryFileName');
  Future<File> _activeFile() async =>
      File('${(await _documentsDirectory()).path}/$_activeFileName');

  Future<List<AiCharacter>> loadAllCharacters() async {
    final file = await _registryFile();
    if (!await file.exists()) {
      await saveAllCharacters(const []);
      return const [];
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(AiCharacter.fromJson)
          .where((character) => character.id.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Import must not treat a damaged registry as an empty installation.
  Future<List<AiCharacter>> loadAllCharactersStrict() async {
    final file = await _registryFile();
    if (!await file.exists()) return [];
    final raw = jsonDecode(await file.readAsString());
    if (raw is! List ||
        raw.any(
          (e) =>
              e is! Map ||
              e['id'] is! String ||
              (e['id'] as String).trim().isEmpty,
        )) {
      throw const FormatException('Invalid character registry');
    }
    return raw.map((e) => AiCharacter.fromJson(e as Map)).toList();
  }

  Future<List<AiCharacter>> loadCharacters() async {
    final characters = await loadAllCharacters();
    if (await DeveloperEnvironmentService().isEnabled()) return characters;
    return characters
        .where((item) => item.id != AiCharacter.defaultCharacterId)
        .toList();
  }

  Future<void> saveAllCharacters(List<AiCharacter> characters) async {
    final file = await _registryFile();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(characters.map((item) => item.toJson()).toList()),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<void> saveCharacters(List<AiCharacter> characters) async {
    final all = await loadAllCharacters();
    final privateCharacters = all.where(
      (item) => item.id == AiCharacter.defaultCharacterId,
    );
    await saveAllCharacters([
      ...privateCharacters,
      ...characters.where((item) => item.id != AiCharacter.defaultCharacterId),
    ]);
  }

  Future<void> addCharacter(AiCharacter character) async {
    final characters = await loadAllCharactersStrict();
    final index = characters.indexWhere((item) => item.id == character.id);
    if (index >= 0) {
      characters[index] = character;
    } else {
      characters.add(character);
    }
    await saveAllCharacters(characters);
  }

  Future<void> updateCharacter(AiCharacter character) =>
      addCharacter(character);

  Future<void> deleteCharacter(String characterId) async {
    if (characterId == AiCharacter.defaultCharacterId) {
      throw StateError('开发者私有角色不能删除，只能通过环境隔离隐藏。');
    }
    final characters = await loadAllCharactersStrict();
    characters.removeWhere((item) => item.id == characterId);
    await saveAllCharacters(characters);
    final activeId = await loadActiveCharacterId();
    if (activeId == characterId) {
      final visible = await loadCharacters();
      if (visible.isNotEmpty) await setActiveCharacter(visible.first.id);
    }
  }

  Future<String> loadActiveCharacterId() async {
    final characters = await loadCharacters();
    if (characters.isEmpty) return '';
    final file = await _activeFile();
    if (!await file.exists()) {
      await setActiveCharacter(characters.first.id);
      return characters.first.id;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      final id = decoded is Map ? decoded['characterId']?.toString() : null;
      return characters.any((item) => item.id == id)
          ? id!
          : characters.first.id;
    } catch (_) {
      return characters.first.id;
    }
  }

  Future<AiCharacter> loadActiveCharacter() async {
    final characters = await loadCharacters();
    if (characters.isEmpty) throw StateError('当前环境还没有角色。');
    final activeId = await loadActiveCharacterId();
    return characters.firstWhere(
      (item) => item.id == activeId,
      orElse: () => characters.first,
    );
  }

  Future<void> setActiveCharacter(String characterId) async {
    final characters = await loadCharacters();
    if (!characters.any((item) => item.id == characterId)) {
      throw StateError('要切换的角色在当前环境中不可见：$characterId');
    }
    final file = await _activeFile();
    await file.writeAsString(
      jsonEncode({'characterId': characterId}),
      flush: true,
    );
  }
}
