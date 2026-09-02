import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../config/peilink_runtime.dart';

import '../models/ai_character.dart';
import '../models/character_settings.dart';
import 'character_avatar_storage_service.dart';
import 'character_registry_service.dart';
import 'character_settings_storage_service.dart';
import 'character_scope_service.dart';
import 'memory2_storage_service.dart';
import 'pei_memory_payload.dart';
import 'legacy_memory_migration_service.dart';
import 'memory2_mutation_coordinator.dart';

class PeiFileException implements Exception {
  const PeiFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PeiFileCorruptedException extends PeiFileException {
  const PeiFileCorruptedException() : super('文件已损坏或不是有效的 PeiLink 角色文件。');
}

class PeiFileUnsupportedVersionException extends PeiFileException {
  const PeiFileUnsupportedVersionException(int version)
    : super('暂不支持 .pei 文件版本 $version，请更新 PeiLink 后重试。');
}

class PeiCharacterPackage {
  const PeiCharacterPackage({
    required this.version,
    required this.character,
    required this.settings,
    this.avatarBytes,
    this.portraitBytes,
    this.memory,
  });
  final int version;
  final AiCharacter character;
  final CharacterSettings settings;
  final Uint8List? avatarBytes;
  final Uint8List? portraitBytes;
  final PeiMemoryPayload? memory;
}

class PeiImportResult {
  const PeiImportResult({required this.character, required this.renamed});
  final AiCharacter character;
  final bool renamed;
}

class PeiFileService {
  PeiFileService({
    CharacterRegistryService? registry,
    this._avatarStorage = const CharacterAvatarStorageService(),
  }) : _registry = registry ?? CharacterRegistryService();

  static const currentVersion = 1;
  static const maxFileBytes = 25 * 1024 * 1024;
  static const _format = 'peilink.character';

  final CharacterRegistryService _registry;
  final CharacterAvatarStorageService _avatarStorage;

  Future<Uint8List> exportCharacter(
    AiCharacter character,
    CharacterSettings settings, {
    bool includeMemories = false,
  }) async {
    Map<String, dynamic>? portableMemory;
    if (includeMemories) {
      try {
        portableMemory = await Memory2MutationCoordinator.runExclusive(
          character.id,
          () async => (await PeiMemoryPayload.load(character.id)).toJson(),
        );
      } on FormatException {
        throw const PeiFileException('记忆数据存在损坏或不支持的扩展，已取消导出，原始数据未修改。');
      }
    }
    final payload = <String, dynamic>{
      'format': _format,
      'version': includeMemories ? 2 : currentVersion,
      if (includeMemories) 'memory': portableMemory,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'character': {
        'name': character.characterName,
        'remark': character.remark,
        'introduction': character.introduction,
        'relationship': character.relationship,
        'birthday': character.birthday?.toIso8601String(),
        'persona': character.persona,
      },
      'configuration': settings.toJson(),
      'openingGreeting': '',
      'media': {
        'avatar': await _encodeLocalImage(character.avatarPath),
        'portrait': await _encodeLocalImage(character.portraitPath),
      },
      'reserved': {
        'echo': null,
        'bond': null,
        'relationshipGrowth': null,
        'memory': null,
      },
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    if (bytes.length > maxFileBytes) {
      throw const PeiFileException('角色数据包超过 25MB，请更换较小的头像或立绘。');
    }
    return bytes;
  }

  PeiCharacterPackage parse(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const PeiFileCorruptedException();
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map || decoded['format'] != _format) {
        throw const PeiFileCorruptedException();
      }
      final version = decoded['version'];
      if (version is! int) throw const PeiFileCorruptedException();
      if (version != 1 && version != 2) {
        throw PeiFileUnsupportedVersionException(version);
      }
      final rawCharacter = decoded['character'];
      final rawSettings = decoded['configuration'];
      if (rawCharacter is! Map || rawSettings is! Map) {
        throw const PeiFileCorruptedException();
      }
      final name = rawCharacter['name']?.toString().trim() ?? '';
      if (name.isEmpty) throw const PeiFileCorruptedException();
      final character = AiCharacter(
        id: 'pei_import_preview',
        characterName: name,
        remark: rawCharacter['remark']?.toString().trim() ?? '',
        introduction: rawCharacter['introduction']?.toString().trim() ?? '',
        relationship: rawCharacter['relationship']?.toString().trim() ?? '',
        birthday: DateTime.tryParse(rawCharacter['birthday']?.toString() ?? ''),
        persona: rawCharacter['persona']?.toString().trim() ?? '',
        createdAt: DateTime.now(),
      );
      final media = decoded['media'];
      return PeiCharacterPackage(
        version: version,
        character: character,
        settings: CharacterSettings.fromJson(
          rawSettings,
          fallbackDefaults: CharacterSettings.genericDefaults(),
        ),
        avatarBytes: media is Map ? _decodeImage(media['avatar']) : null,
        portraitBytes: media is Map ? _decodeImage(media['portrait']) : null,
        memory: version == 2 ? PeiMemoryPayload.parse(decoded['memory']) : null,
      );
    } on PeiFileException {
      rethrow;
    } catch (_) {
      throw const PeiFileCorruptedException();
    }
  }

  Future<PeiImportResult> importCharacter(PeiCharacterPackage package) async {
    if (package.version != 1 && package.version != 2) {
      throw PeiFileUnsupportedVersionException(package.version);
    }
    if (package.version == 2 && package.memory == null ||
        package.version == 1 && package.memory != null) {
      throw const PeiFileCorruptedException();
    }
    // Revalidate even a programmatically supplied preview before any writes.
    final memory = package.memory == null
        ? null
        : PeiMemoryPayload.parse(package.memory!.toJson());
    final existing = await _registry.loadAllCharactersStrict();
    final importedName = uniqueName(
      package.character.characterName,
      existing.map((item) => item.characterName),
    );
    final now = DateTime.now();
    var sequence = now.microsecondsSinceEpoch;
    var id = 'character_$sequence';
    final documents = await getApplicationDocumentsDirectory();
    while (existing.any((e) => e.id == id) ||
        await Directory('${documents.path}/characters/$id').exists()) {
      id = 'character_${++sequence}';
    }
    var avatarPath = '';
    var portraitPath = '';
    try {
      if (package.avatarBytes != null) {
        avatarPath = await _avatarStorage.saveAvatarBytes(
          characterId: id,
          bytes: package.avatarBytes!,
        );
      }
      if (package.portraitBytes != null) {
        portraitPath = await _avatarStorage.savePortraitBytes(
          characterId: id,
          bytes: package.portraitBytes!,
        );
      }
      final character = AiCharacter(
        id: id,
        characterName: importedName,
        remark: package.character.remark,
        avatarPath: avatarPath,
        portraitPath: portraitPath,
        introduction: package.character.introduction,
        characterIntro: package.character.characterIntro,
        relationship: package.character.relationship,
        birthday: package.character.birthday,
        persona: package.character.persona,
        createdAt: now,
        isBuiltIn: false,
      );
      await CharacterSettingsStorageService(characterId: id).saveSettings(
        package.settings.copyWith(
          characterName: importedName,
          introduction: character.introduction,
        ),
      );
      if (memory != null) {
        final storage = Memory2StorageService(characterId: id);
        final legacyFile = await CharacterScopeService(
          id,
        ).dataFile('memories.json');
        final links = <String, dynamic>{};
        final legacyRows = memory.legacy.map((row) {
          final copy = Map<String, dynamic>.from(row);
          final link = copy.remove('memory2Reference');
          final source = LegacyMemoryMigrationService.parseEntry(copy)?.id;
          if (link != null && source != null) links[source] = link;
          return copy;
        }).toList();
        await legacyFile.writeAsString(jsonEncode(legacyRows), flush: true);
        await storage.saveEventMemories(memory.events);
        await storage.saveUserMemories(memory.users);
        await storage.saveMemorySummary(memory.summary);
        if (links.isNotEmpty) {
          final file = await CharacterScopeService(
            id,
          ).dataFile(LegacyMemoryMigrationService.ledgerFile);
          await file.writeAsString(
            jsonEncode({'version': 1, 'links': links}),
            flush: true,
          );
        }
      }
      await _registry.addCharacter(character);
      return PeiImportResult(
        character: character,
        renamed: importedName != package.character.characterName,
      );
    } catch (_) {
      // Only this newly allocated character directory is rolled back.
      await CharacterScopeService(id).deleteAllData();
      rethrow;
    }
  }

  static String uniqueName(String requested, Iterable<String> existingNames) {
    final used = existingNames.map((item) => item.trim()).toSet();
    final base = requested.trim().isEmpty ? '未命名 AI' : requested.trim();
    if (!used.contains(base)) return base;
    var suffix = 2;
    while (used.contains('$base ($suffix)')) {
      suffix++;
    }
    return '$base ($suffix)';
  }

  Future<Map<String, dynamic>?> _encodeLocalImage(String path) async {
    final file = File(path.trim());
    if (path.trim().isEmpty || !await file.exists()) return null;
    return {
      'encoding': 'base64',
      'data': base64Encode(await file.readAsBytes()),
    };
  }

  static Uint8List? _decodeImage(dynamic raw) {
    if (raw is! Map || raw['encoding'] != 'base64') return null;
    final data = raw['data']?.toString() ?? '';
    if (data.isEmpty) return null;
    final bytes = base64Decode(data);
    if (bytes.length > maxFileBytes) throw const PeiFileCorruptedException();
    return Uint8List.fromList(bytes);
  }
}
