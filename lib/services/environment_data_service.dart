import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';
import '../models/ai_character.dart';
import 'character_registry_service.dart';

class EnvironmentDataService {
  final CharacterRegistryService _registry = CharacterRegistryService();

  Future<void> initializeDeveloperSandbox() async {
    if (!PeiLinkRuntime.developerToolsEnabled) {
      throw StateError('当前构建不包含开发者沙盒。');
    }
    // 开发者沙盒不再自动注入任何内置角色，角色由开发者手动创建或导入。
    await _registry.loadAllCharacters();
  }

  Future<void> initializePlayerWorkspace() async {
    // Intentionally empty: a public/test workspace must not receive seed roles.
    await _registry.loadAllCharacters();
  }

  /// Archives player-created role metadata and folders, then returns to an
  /// empty player workspace. Developer-private data is left in place.
  Future<Directory> archiveAndClearPlayerWorkspace() async {
    final documents = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final archive = Directory(
      '${documents.path}/environment_archives/player_$stamp',
    );
    await archive.create(recursive: true);

    final all = await _registry.loadAllCharacters();
    final playerCharacters = all
        .where((item) => item.id != AiCharacter.defaultCharacterId)
        .toList();
    final privateCharacters = all
        .where((item) => item.id == AiCharacter.defaultCharacterId)
        .toList();

    await File('${archive.path}/character_registry.json').writeAsString(
      jsonEncode(playerCharacters.map((item) => item.toJson()).toList()),
      flush: true,
    );

    final charactersRoot = Directory('${documents.path}/characters');
    for (final character in playerCharacters) {
      final safeId = character.id.trim().replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );
      final source = Directory('${charactersRoot.path}/$safeId');
      if (await source.exists()) {
        await source.rename('${archive.path}/$safeId');
      }
    }

    for (final name in const [
      'active_character.json',
      'home_display_character.json',
    ]) {
      final source = File('${documents.path}/$name');
      if (await source.exists()) await source.rename('${archive.path}/$name');
    }

    await _registry.saveAllCharacters(privateCharacters);
    return archive;
  }
}
