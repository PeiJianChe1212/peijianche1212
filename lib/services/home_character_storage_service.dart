import 'dart:convert';

import '../config/peilink_runtime.dart';

import '../models/ai_character.dart';
import '../platform/storage/platform_storage.dart';
import 'character_registry_service.dart';

class HomeCharacterStorageService {
  HomeCharacterStorageService({PlatformStorage? storage})
    : _storage = storage,
      _registry = CharacterRegistryService(storage: storage);

  static const String _fileName = 'home_display_character.json';

  final CharacterRegistryService _registry;
  final PlatformStorage? _storage;

  Future<PlatformStorage> _platformStorage() =>
      _storage == null ? PeiLinkRuntime.storage() : Future.value(_storage);

  Future<String> loadCharacterId() async {
    final characters = await _registry.loadCharacters();
    final storage = await _platformStorage();
    if (!await storage.exists(_fileName)) {
      final activeId = await _registry.loadActiveCharacterId();
      await saveCharacterId(activeId);
      return activeId;
    }

    try {
      final decoded = jsonDecode(await storage.readText(_fileName));
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
    final storage = await _platformStorage();
    await storage.writeText(
      _fileName,
      jsonEncode({'characterId': characterId}),
    );
  }
}
