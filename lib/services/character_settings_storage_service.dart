import 'dart:convert';
import '../models/ai_character.dart';
import '../models/character_settings.dart';
import '../platform/storage/platform_storage.dart';
import 'character_registry_service.dart';
import 'character_scope_service.dart';

class CharacterSettingsStorageService {
  CharacterSettingsStorageService({
    this.characterId,
    this.storage,
    CharacterRegistryService? registry,
  }) : _registry = registry ?? CharacterRegistryService(storage: storage);

  final String? characterId;
  final PlatformStorage? storage;
  final CharacterRegistryService _registry;

  Future<String> _resolvedId() async {
    final explicit = characterId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return _registry.loadActiveCharacterId();
  }

  Future<(PlatformStorage, String)> _location(String name) async {
    final scope = CharacterScopeService(characterId);
    return (
      storage ?? await scope.storage(),
      await scope.dataKey(name, legacyDefaultFileName: name),
    );
  }

  Future<CharacterSettings> loadSettings() async {
    final (store, key) = await _location('character_settings.json');

    if (!await store.exists(key)) {
      final id = await _resolvedId();
      final settings = id == AiCharacter.defaultCharacterId
          ? await _migrateLegacyChatSettings()
          : await _createSettingsFromRegistry(id);
      await saveSettings(settings);
      return settings;
    }

    try {
      final raw = await store.readText(key);
      if (raw.trim().isEmpty) return _fallbackSettings();

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _fallbackSettings();

      final id = await _resolvedId();
      final fallback = id == AiCharacter.defaultCharacterId
          ? CharacterSettings.defaults()
          : CharacterSettings.genericDefaults();
      final saved = CharacterSettings.fromJson(
        decoded,
        fallbackDefaults: fallback,
      );
      // Persisted values are user data. Content alone does not establish
      // whether a field came from a historical default or an explicit edit.
      return await _reconcileIdentityWithRegistry(saved);
    } catch (_) {
      if (store is FailFastPlatformStorage) rethrow;
      return _fallbackSettings();
    }
  }

  /// 姓名、备注、关系和简介同时存在于角色登记册与角色设置中。
  /// 旧版本创建角色时，设置文件可能错误继承默认角色的“老裴”等资料。
  /// 从 v1.4.4 起，登记册作为这些公开资料的唯一准绳，加载时自动修正旧数据。
  Future<CharacterSettings> _reconcileIdentityWithRegistry(
    CharacterSettings saved,
  ) async {
    final id = await _resolvedId();
    final characters = await _registry.loadCharacters();
    final index = characters.indexWhere((item) => item.id == id);
    if (index < 0) return saved;

    final character = characters[index];
    final birthday = character.birthday;
    final registryBirthday = birthday == null
        ? saved.birthday
        : '${birthday.month}月${birthday.day}日';
    final registryRelation = character.relationship.trim().isEmpty
        ? saved.relation
        : character.relationship.trim();

    final reconciled = saved.copyWith(
      characterName: character.characterName,
      remark: character.remark,
      relation: registryRelation,
      birthday: registryBirthday,
      introduction: character.introduction,
    );

    if (reconciled.characterName != saved.characterName ||
        reconciled.remark != saved.remark ||
        reconciled.relation != saved.relation ||
        reconciled.birthday != saved.birthday ||
        reconciled.introduction != saved.introduction) {
      await saveSettings(reconciled);
    }
    return reconciled;
  }

  Future<CharacterSettings> _fallbackSettings() async {
    final id = await _resolvedId();
    if (id == AiCharacter.defaultCharacterId) {
      return CharacterSettings.defaults();
    }
    return _createSettingsFromRegistry(id);
  }

  Future<CharacterSettings> _createSettingsFromRegistry(String id) async {
    final characters = await _registry.loadCharacters();
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
    final (store, key) = await _location('chat_settings.json');

    if (!await store.exists(key)) return defaults;

    try {
      final raw = await store.readText(key);
      if (raw.trim().isEmpty) return defaults;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return defaults;

      String readMode() {
        final value = decoded['conversationMode']?.toString();
        return const {
              'basic',
              'heart',
              'delicate',
              'long',
              'deep',
            }.contains(value)
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
    final (store, key) = await _location('character_settings.json');
    await store.writeText(key, jsonEncode(settings.toJson()));
  }

  Future<void> restoreDefaults() async {
    final id = await _resolvedId();
    final settings = id == AiCharacter.defaultCharacterId
        ? CharacterSettings.defaults()
        : await _createSettingsFromRegistry(id);
    await saveSettings(settings);
  }
}
