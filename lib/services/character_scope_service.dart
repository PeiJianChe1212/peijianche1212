import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/ai_character.dart';
import 'character_registry_service.dart';

class CharacterScopeService {
  const CharacterScopeService([this.characterId]);

  final String? characterId;

  static String sanitizeCharacterId(String value) {
    final normalized = value.trim().replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    return normalized.isEmpty ? AiCharacter.defaultCharacterId : normalized;
  }

  Future<String> resolveCharacterId() async {
    final explicit = characterId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    return CharacterRegistryService().loadActiveCharacterId();
  }

  Future<Directory> characterDirectory() async {
    final resolvedId = sanitizeCharacterId(await resolveCharacterId());
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/characters/$resolvedId');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> dataFile(
    String fileName, {
    String? legacyDefaultFileName,
  }) async {
    final resolvedId = sanitizeCharacterId(await resolveCharacterId());
    final documents = await getApplicationDocumentsDirectory();

    if (resolvedId == AiCharacter.defaultCharacterId) {
      return File(
        '${documents.path}/${legacyDefaultFileName ?? fileName}',
      );
    }

    final directory = await characterDirectory();
    return File('${directory.path}/$fileName');
  }

  Future<Directory> avatarDirectory() async {
    final directory = await characterDirectory();
    final avatars = Directory('${directory.path}/avatar');
    if (!await avatars.exists()) {
      await avatars.create(recursive: true);
    }
    return avatars;
  }

  Future<void> deleteAllData() async {
    final resolvedId = sanitizeCharacterId(await resolveCharacterId());
    if (resolvedId == AiCharacter.defaultCharacterId) {
      throw StateError('默认角色的数据不能通过该方法直接删除。');
    }

    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/characters/$resolvedId');
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
