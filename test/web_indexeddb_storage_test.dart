@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/memory_extraction_state.dart';
import 'package:peijianche_app/platform/storage/platform_storage.dart';
import 'package:peijianche_app/platform/storage/web_indexeddb_platform_storage.dart';
import 'package:peijianche_app/services/character_profile_storage_service.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/character_settings_storage_service.dart';
import 'package:peijianche_app/services/chat_storage_service.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';
import 'package:peijianche_app/services/memory_extraction_state_service.dart';

void main() {
  late String namespace;
  late WebIndexedDbPlatformStorage storage;

  setUp(() async {
    namespace = 'test_${DateTime.now().microsecondsSinceEpoch}';
    storage = await WebIndexedDbPlatformStorage.open(namespace);
  });

  tearDown(() async => storage.delete('', recursive: true));

  test('IndexedDB text and bytes CRUD survives reopening', () async {
    await storage.writeText('a/value.json', '{"v":1}');
    await storage.writeBytes('a/value.bin', Uint8List.fromList([1, 2, 3]));
    final reopened = await WebIndexedDbPlatformStorage.open(namespace);
    expect(await reopened.readText('a/value.json'), '{"v":1}');
    expect(await reopened.readBytes('a/value.bin'), [1, 2, 3]);
    expect((await reopened.list('a', recursive: true)).length, 2);
    await reopened.delete('a/value.json');
    expect(await reopened.exists('a/value.json'), isFalse);
  });

  test('user and dev namespaces never share keys', () async {
    final user = await WebIndexedDbPlatformStorage.open('${namespace}_user');
    final dev = await WebIndexedDbPlatformStorage.open('${namespace}_dev');
    await user.writeText('character_registry.json', 'user');
    await dev.writeText('character_registry.json', 'dev');
    expect(await user.readText('character_registry.json'), 'user');
    expect(await dev.readText('character_registry.json'), 'dev');
    await user.delete('', recursive: true);
    await dev.delete('', recursive: true);
  });

  test(
    'stale writer is rejected and committed value remains complete',
    () async {
      final first = await WebIndexedDbPlatformStorage.open(namespace);
      final stale = await WebIndexedDbPlatformStorage.open(namespace);
      await first.writeText('registry.json', 'original');
      expect(await first.readText('registry.json'), 'original');
      expect(await stale.readText('registry.json'), 'original');
      await first.replaceTextSafely('registry.json', 'new-complete-value');
      await expectLater(
        stale.replaceTextSafely('registry.json', 'stale-value'),
        throwsA(isA<PlatformStorageConflictException>()),
      );
      final reopened = await WebIndexedDbPlatformStorage.open(namespace);
      expect(await reopened.readText('registry.json'), 'new-complete-value');
    },
  );

  test(
    'missing registry is empty but corrupted registry fails without overwrite',
    () async {
      final registry = CharacterRegistryService(storage: storage);
      expect(await registry.loadAllCharacters(), isEmpty);
      await storage.writeText('character_registry.json', '{broken');
      await expectLater(registry.loadAllCharacters(), throwsFormatException);
      expect(await storage.readText('character_registry.json'), '{broken');
    },
  );

  test(
    'two characters, settings, profiles, chat and active survive reopening',
    () async {
      final registry = CharacterRegistryService(storage: storage);
      final a = _character('Web_A', 'Web A');
      final b = _character('Web_B', 'Web B');
      await registry.addCharacter(a);
      await registry.addCharacter(b);
      await registry.setActiveCharacter(b.id);
      await _saveCharacterData(storage, registry, a, 'A text');
      await _saveCharacterData(storage, registry, b, 'B text');

      final reopened = await WebIndexedDbPlatformStorage.open(namespace);
      final reopenedRegistry = CharacterRegistryService(storage: reopened);
      expect((await reopenedRegistry.loadCharacters()).map((e) => e.id), [
        'Web_A',
        'Web_B',
      ]);
      expect(await reopenedRegistry.loadActiveCharacterId(), 'Web_B');
      expect(
        (await ChatStorageService(
          characterId: 'Web_A',
          storage: reopened,
        ).loadMessages()).single.content,
        'A text',
      );
      expect(
        (await ChatStorageService(
          characterId: 'Web_B',
          storage: reopened,
        ).loadMessages()).single.content,
        'B text',
      );
    },
  );

  test(
    'editing settings and profile replaces values without losing other fields',
    () async {
      final registry = CharacterRegistryService(storage: storage);
      final original = _character('Web_A', 'Web A');
      await registry.addCharacter(original);
      final settingsService = CharacterSettingsStorageService(
        characterId: original.id,
        storage: storage,
        registry: registry,
      );
      final originalSettings = CharacterSettings.fromAiCharacter(original);
      await settingsService.saveSettings(
        originalSettings.copyWith(coreProfile: 'long original', relation: '朋友'),
      );
      final updated = original.copyWith(characterName: 'Web A Edited');
      await registry.updateCharacter(updated);
      await settingsService.saveSettings(
        (await settingsService.loadSettings()).copyWith(
          coreProfile: 'long edited value',
        ),
      );
      final profileService = CharacterProfileStorageService(
        characterId: original.id,
        storage: storage,
      );
      await profileService.save(
        CharacterProfile(
          characterId: original.id,
          name: 'Web A Edited',
          age: '28',
        ),
      );

      final reopened = await WebIndexedDbPlatformStorage.open(namespace);
      final reopenedRegistry = CharacterRegistryService(storage: reopened);
      final loadedCharacter = (await reopenedRegistry.loadCharacters()).single;
      final loadedSettings = await CharacterSettingsStorageService(
        characterId: original.id,
        storage: reopened,
        registry: reopenedRegistry,
      ).loadSettings();
      final loadedProfile = await CharacterProfileStorageService(
        characterId: original.id,
        storage: reopened,
      ).load(character: loadedCharacter, legacySettings: loadedSettings);
      expect(loadedCharacter.characterName, 'Web A Edited');
      expect(loadedSettings.coreProfile, 'long edited value');
      expect(loadedSettings.relation, '朋友');
      expect(loadedProfile.name, 'Web A Edited');
      expect(loadedProfile.age, '28');
    },
  );

  test(
    'recursive character delete removes A scope without affecting B',
    () async {
      await storage.writeText('characters/Web_A/a.json', 'A');
      await storage.writeText('characters/Web_A/nested/b.json', 'A2');
      await storage.writeText('characters/Web_B/a.json', 'B');
      await storage.delete('characters/Web_A', recursive: true);
      final reopened = await WebIndexedDbPlatformStorage.open(namespace);
      expect(await reopened.list('characters/Web_A', recursive: true), isEmpty);
      expect(await reopened.readText('characters/Web_B/a.json'), 'B');
    },
  );

  test('Memory event and extraction cursor retain strict parity', () async {
    final memory = Memory2StorageService(
      characterId: 'Web_A',
      platformStorage: storage,
    );
    final event = EventMemory(
      id: 'e1',
      characterId: 'Web_A',
      content: 'fictional event',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await memory.saveEventMemories([event]);
    expect(
      (await memory.loadEventMemoriesStrict()).single.toJson(),
      event.toJson(),
    );
    final state = MemoryExtractionStateService(
      characterId: 'Web_A',
      platformStorage: storage,
    );
    await state.save(
      const MemoryExtractionState(
        characterId: 'Web_A',
        lastProcessedMessageId: 'cursor-1',
      ),
    );
    expect((await state.loadStrict()).lastProcessedMessageId, 'cursor-1');
  });
}

AiCharacter _character(String id, String name) => AiCharacter(
  id: id,
  characterName: name,
  remark: '',
  createdAt: DateTime.utc(2026, 1, 1),
);

Future<void> _saveCharacterData(
  PlatformStorage storage,
  CharacterRegistryService registry,
  AiCharacter character,
  String chatText,
) async {
  final settings = CharacterSettings.fromAiCharacter(character);
  await CharacterSettingsStorageService(
    characterId: character.id,
    storage: storage,
    registry: registry,
  ).saveSettings(settings);
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
    ChatMessage(role: 'user', content: chatText, id: 'message-${character.id}'),
  ]);
}
