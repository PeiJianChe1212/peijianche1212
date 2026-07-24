import 'dart:convert';
import 'dart:io';

import '../models/ai_character.dart';
import '../models/character_settings.dart';
import 'character_registry_service.dart';
import 'character_scope_service.dart';

class CharacterSettingsStorageService {
  CharacterSettingsStorageService({this.characterId});

  final String? characterId;

  Future<String> _resolvedId() async {
    final explicit = characterId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return CharacterRegistryService().loadActiveCharacterId();
  }

  Future<File> _settingsFile() {
    return CharacterScopeService(characterId).dataFile(
      'character_settings.json',
      legacyDefaultFileName: 'character_settings.json',
    );
  }

  Future<File> _legacyChatSettingsFile() {
    return CharacterScopeService(characterId).dataFile(
      'chat_settings.json',
      legacyDefaultFileName: 'chat_settings.json',
    );
  }

  Future<CharacterSettings> loadSettings() async {
    final file = await _settingsFile();

    if (!await file.exists()) {
      final id = await _resolvedId();
      final settings = id == AiCharacter.defaultCharacterId
          ? await _migrateLegacyChatSettings()
          : await _createSettingsFromRegistry(id);
      await saveSettings(settings);
      return settings;
    }

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return _fallbackSettings();

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _fallbackSettings();

      return CharacterSettings.fromJson(decoded);
    } catch (_) {
      return _fallbackSettings();
    }
  }

  Future<CharacterSettings> _fallbackSettings() async {
    final id = await _resolvedId();
    if (id == AiCharacter.defaultCharacterId) {
      return CharacterSettings.defaults();
    }
    return _createSettingsFromRegistry(id);
  }

  Future<CharacterSettings> _createSettingsFromRegistry(String id) async {
    final characters = await CharacterRegistryService().loadCharacters();
    final character = characters.firstWhere(
      (item) => item.id == id,
      orElse: () => AiCharacter(
        id: id,
        characterName: '未命名 AI',
        remark: '',
        createdAt: DateTime.now(),
      ),
    );
    return CharacterSettings.fromAiCharacter(character);
  }

  Future<CharacterSettings> _migrateLegacyChatSettings() async {
    final defaults = CharacterSettings.defaults();
    final legacyFile = await _legacyChatSettingsFile();

    if (!await legacyFile.exists()) return defaults;

    try {
      final raw = await legacyFile.readAsString();
      if (raw.trim().isEmpty) return defaults;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return defaults;

      String readMode() {
        final value = decoded['conversationMode']?.toString();
        return const {'basic', 'heart', 'delicate', 'long', 'deep'}
                .contains(value)
            ? value!
            : defaults.conversationMode;
      }

      String readReplyLength() {
        final value = decoded['replyLength']?.toString();
        return const {'short', 'standard', 'long'}.contains(value)
            ? value!
            : defaults.replyLength;
      }

      double readDouble(String key, double fallback, double min, double max) {
        final value = decoded[key];
        return value is num
            ? value.toDouble().clamp(min, max).toDouble()
            : fallback;
      }

      int readInt(String key, int fallback, int min, int max) {
        final value = decoded[key];
        return value is num ? value.toInt().clamp(min, max).toInt() : fallback;
      }

      return defaults.copyWith(
        conversationMode: readMode(),
        temperature: readDouble(
          'temperature',
          defaults.temperature,
          0.55,
          0.90,
        ),
        replyLength: readReplyLength(),
        initiative: readDouble('initiative', defaults.initiative, 0, 1),
        intimacy: readDouble('intimacy', defaults.intimacy, 0, 1),
        tsundere: readDouble('tsundere', defaults.tsundere, 0, 1),
        proactiveEnabled: decoded['proactiveEnabled'] is bool
            ? decoded['proactiveEnabled'] as bool
            : defaults.proactiveEnabled,
        lateNightMessages: decoded['lateNightMessages'] is bool
            ? decoded['lateNightMessages'] as bool
            : defaults.lateNightMessages,
        maxProactivePerDay: readInt(
          'maxProactivePerDay',
          defaults.maxProactivePerDay,
          0,
          4,
        ),
      );
    } catch (_) {
      return defaults;
    }
  }

  Future<void> saveSettings(CharacterSettings settings) async {
    final file = await _settingsFile();
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }

  Future<void> restoreDefaults() async {
    final id = await _resolvedId();
    final settings = id == AiCharacter.defaultCharacterId
        ? CharacterSettings.defaults()
        : await _createSettingsFromRegistry(id);
    await saveSettings(settings);
  }
}
