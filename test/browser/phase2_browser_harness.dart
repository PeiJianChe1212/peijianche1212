import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/platform/storage/web_indexeddb_platform_storage.dart';
import 'package:peijianche_app/services/character_profile_storage_service.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/character_settings_storage_service.dart';
import 'package:peijianche_app/services/chat_storage_service.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  try {
    final result = await _advanceAcceptanceStage();
    _publishResult(result);
  } catch (error, stackTrace) {
    final result = 'PHASE2_BROWSER_FAIL\n$error\n$stackTrace';
    _publishResult(result);
  }
}

void _publishResult(String result) {
  final node = web.document.createElement('pre') as web.HTMLPreElement
    ..id = 'phase2-result'
    ..textContent = result;
  web.document.body?.append(node);
}

Future<String> _advanceAcceptanceStage() async {
  final storage = await WebIndexedDbPlatformStorage.open('peilink_user');
  const markerKey = '_phase2_acceptance_stage.txt';
  final stage = await storage.exists(markerKey)
      ? int.parse(await storage.readText(markerKey))
      : 0;
  final registry = CharacterRegistryService(storage: storage);
  final a = _character('Web_A', stage < 2 ? 'Web A' : 'Web A Edited');
  final b = _character('Web_B', 'Web B');

  if (stage == 0) {
    expect(
      (await registry.loadCharacters()).isEmpty,
      'fresh registry not empty',
    );
    await registry.addCharacter(a);
    await registry.addCharacter(b);
    await _saveData(storage, registry, a, 'A original long field', 'A profile');
    await _saveData(storage, registry, b, 'B isolated long field', 'B profile');
    await registry.setActiveCharacter(a.id);
    await storage.writeText(markerKey, '1');
    return 'PHASE2_BROWSER_STAGE_1_CREATED';
  }

  if (stage == 1) {
    expect(
      (await registry.loadCharacters()).map((e) => e.id).join(',') ==
          'Web_A,Web_B',
      'characters lost after reload',
    );
    expect(await registry.loadActiveCharacterId() == 'Web_A', 'active A lost');
    expect(
      await _chat(storage, 'Web_B') == 'B profile',
      'B chat isolation failed',
    );
    final edited = _character('Web_A', 'Web A Edited');
    await registry.updateCharacter(edited);
    final settingsService = CharacterSettingsStorageService(
      characterId: edited.id,
      storage: storage,
      registry: registry,
    );
    final old = await settingsService.loadSettings();
    await settingsService.saveSettings(
      old.copyWith(coreProfile: 'A edited complete long field'),
    );
    await CharacterProfileStorageService(
      characterId: edited.id,
      storage: storage,
    ).save(
      CharacterProfile(
        characterId: edited.id,
        name: edited.characterName,
        age: '28',
      ),
    );
    await registry.setActiveCharacter(b.id);
    await storage.writeText(markerKey, '2');
    return 'PHASE2_BROWSER_STAGE_2_EDITED';
  }

  if (stage == 2) {
    final characters = await registry.loadCharacters();
    expect(
      characters.firstWhere((e) => e.id == 'Web_A').characterName ==
          'Web A Edited',
      'edited name lost',
    );
    expect(await registry.loadActiveCharacterId() == 'Web_B', 'active B lost');
    final settings = await CharacterSettingsStorageService(
      characterId: 'Web_A',
      storage: storage,
      registry: registry,
    ).loadSettings();
    expect(
      settings.coreProfile == 'A edited complete long field',
      'edited settings lost',
    );
    final profile =
        await CharacterProfileStorageService(
          characterId: 'Web_A',
          storage: storage,
        ).load(
          character: characters.firstWhere((e) => e.id == 'Web_A'),
          legacySettings: settings,
        );
    expect(profile.age == '28', 'edited profile lost');
    await registry.deleteCharacter('Web_A');
    await storage.delete('characters/Web_A', recursive: true);
    await storage.writeText(markerKey, '3');
    return 'PHASE2_BROWSER_STAGE_3_DELETED';
  }

  final characters = await registry.loadCharacters();
  expect(
    characters.length == 1 && characters.single.id == 'Web_B',
    'deleted A revived or B was affected',
  );
  expect(
    await registry.loadActiveCharacterId() == 'Web_B',
    'active B invalid after delete',
  );
  expect(
    (await storage.list('characters/Web_A', recursive: true)).isEmpty,
    'A scope survived delete',
  );
  expect(
    await _chat(storage, 'Web_B') == 'B profile',
    'B data changed after deleting A',
  );
  return 'PHASE2_BROWSER_PASS';
}

void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

AiCharacter _character(String id, String name) => AiCharacter(
  id: id,
  characterName: name,
  remark: '',
  createdAt: DateTime.utc(2026, 1, 1),
);

Future<void> _saveData(
  WebIndexedDbPlatformStorage storage,
  CharacterRegistryService registry,
  AiCharacter character,
  String coreProfile,
  String chat,
) async {
  await CharacterSettingsStorageService(
    characterId: character.id,
    storage: storage,
    registry: registry,
  ).saveSettings(
    CharacterSettings.fromAiCharacter(
      character,
    ).copyWith(coreProfile: coreProfile),
  );
  await CharacterProfileStorageService(
    characterId: character.id,
    storage: storage,
  ).save(
    CharacterProfile(characterId: character.id, name: character.characterName),
  );
  await ChatStorageService(
    characterId: character.id,
    storage: storage,
  ).saveMessages([
    ChatMessage(id: 'm-${character.id}', role: 'user', content: chat),
  ]);
}

Future<String> _chat(WebIndexedDbPlatformStorage storage, String id) async =>
    (await ChatStorageService(
      characterId: id,
      storage: storage,
    ).loadMessages()).single.content;
