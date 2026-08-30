import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/ai_character.dart';
import '../models/character_settings.dart';
import 'character_avatar_storage_service.dart';
import 'character_registry_service.dart';
import 'character_settings_storage_service.dart';

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
  });
  final int version;
  final AiCharacter character;
  final CharacterSettings settings;
  final Uint8List? avatarBytes;
  final Uint8List? portraitBytes;
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
    CharacterSettings settings,
  ) async {
    final payload = <String, dynamic>{
      'format': _format,
      'version': currentVersion,
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
      if (version != currentVersion) {
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
      );
    } on PeiFileException {
      rethrow;
    } catch (_) {
      throw const PeiFileCorruptedException();
    }
  }

  Future<PeiImportResult> importCharacter(PeiCharacterPackage package) async {
    final existing = await _registry.loadAllCharacters();
    final importedName = uniqueName(
      package.character.characterName,
      existing.map((item) => item.characterName),
    );
    final now = DateTime.now();
    final id = 'character_${now.microsecondsSinceEpoch}';
    var avatarPath = '';
    var portraitPath = '';
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
    await _registry.addCharacter(character);
    return PeiImportResult(
      character: character,
      renamed: importedName != package.character.characterName,
    );
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
