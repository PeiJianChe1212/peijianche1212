import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/peilink_runtime.dart';

import '../models/ai_character.dart';
import '../platform/storage/platform_storage.dart';
import 'developer_environment_service.dart';

class CharacterRegistryService {
  CharacterRegistryService({this.storage});

  final PlatformStorage? storage;
  static const String _registryFileName = 'character_registry.json';
  static const String _activeFileName = 'active_character.json';
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  Future<PlatformStorage> _platformStorage() =>
      storage == null ? PeiLinkRuntime.storage() : Future.value(storage);

  Future<List<AiCharacter>> loadAllCharacters() async {
    final storage = await _platformStorage();
    if (!await storage.exists(_registryFileName)) {
      await saveAllCharacters(const []);
      return const [];
    }
    try {
      final decoded = jsonDecode(await storage.readText(_registryFileName));
      if (decoded is! List ||
          decoded.any(
            (e) =>
                e is! Map ||
                e['id'] is! String ||
                (e['id'] as String).trim().isEmpty,
          )) {
        throw const FormatException('Invalid character registry');
      }
      return decoded.map((e) => AiCharacter.fromJson(e as Map)).toList();
    } catch (_) {
      if (storage is FailFastPlatformStorage) rethrow;
      return const [];
    }
  }

  /// Import must not treat a damaged registry as an empty installation.
  Future<List<AiCharacter>> loadAllCharactersStrict() async {
    final storage = await _platformStorage();
    if (!await storage.exists(_registryFileName)) return [];
    final raw = jsonDecode(await storage.readText(_registryFileName));
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
    final storage = await _platformStorage();
    await storage.replaceTextSafely(
      _registryFileName,
      jsonEncode(characters.map((item) => item.toJson()).toList()),
    );
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
    changes.value++;
  }

  Future<void> updateCharacter(AiCharacter character) =>
      addCharacter(character);

  Future<void> deleteCharacter(String characterId) async {
    if (characterId == AiCharacter.defaultCharacterId) {
      throw StateError('开发者私有角色不能删除，只能通过环境隔离隐藏。');
    }
    final characters = await loadAllCharactersStrict();
    final activeId = await loadActiveCharacterId();
    characters.removeWhere((item) => item.id == characterId);
    await saveAllCharacters(characters);
    if (activeId == characterId) {
      final visible = await loadCharacters();
      final storage = await _platformStorage();
      if (visible.isEmpty) {
        await storage.delete(_activeFileName);
      } else {
        await setActiveCharacter(visible.first.id);
      }
    }
  }

  Future<String> loadActiveCharacterId() async {
    final characters = await loadCharacters();
    if (characters.isEmpty) return '';
    final storage = await _platformStorage();
    if (!await storage.exists(_activeFileName)) {
      await setActiveCharacter(characters.first.id);
      return characters.first.id;
    }
    try {
      final decoded = jsonDecode(await storage.readText(_activeFileName));
      if (decoded is! Map || decoded['characterId'] is! String) {
        throw const FormatException('Invalid active character record');
      }
      final id = decoded['characterId'] as String;
      return characters.any((item) => item.id == id) ? id : characters.first.id;
    } catch (_) {
      if (storage is FailFastPlatformStorage) rethrow;
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
    final storage = await _platformStorage();
    await storage.writeText(
      _activeFileName,
      jsonEncode({'characterId': characterId}),
    );
  }
}
