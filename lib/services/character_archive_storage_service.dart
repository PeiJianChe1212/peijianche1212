import 'dart:convert';
import 'dart:io';

import '../models/character_archive.dart';
import 'character_scope_service.dart';

class CharacterArchiveStorageService {
  const CharacterArchiveStorageService({
    required this.characterId,
    this.fileProvider,
  });

  final String characterId;
  final Future<File> Function(String characterId)? fileProvider;

  Future<File> _file() {
    final provider = fileProvider;
    if (provider != null) return provider(characterId);
    return CharacterScopeService(
      characterId,
    ).dataFile('character_archive.json');
  }

  Future<CharacterArchive> load() async {
    final empty = CharacterArchive(characterId: characterId);
    try {
      final file = await _file();
      if (!await file.exists()) return empty;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map
          ? CharacterArchive.fromJson(decoded, characterId)
          : empty;
    } catch (_) {
      return empty;
    }
  }

  Future<void> save(CharacterArchive archive) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final scopedArchive = CharacterArchive(
      characterId: characterId,
      values: archive.values,
    );
    await file.writeAsString(jsonEncode(scopedArchive.toJson()), flush: true);
  }

  Future<void> initialize() async {
    final file = await _file();
    if (await file.exists()) return;
    await save(CharacterArchive(characterId: characterId));
  }
}
