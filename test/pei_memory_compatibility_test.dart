import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/memory_source_type.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/character_scope_service.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';
import 'package:peijianche_app/services/pei_file_service.dart';
import 'package:peijianche_app/services/legacy_memory_migration_service.dart';
import 'package:peijianche_app/services/memory_source_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('peilink_pei_memory_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documents.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  test('v1 export is the default and contains no private memory', () async {
    final character = _character('v1');
    await CharacterScopeService(character.id)
        .dataFile('memories.json')
        .then((file) => file.writeAsString('[{"content":"private sentinel"}]'));
    await CharacterScopeService(character.id)
        .dataFile('archive.json')
        .then((file) => file.writeAsString('{"content":"archive sentinel"}'));
    final bytes = await PeiFileService().exportCharacter(
      character,
      CharacterSettings.fromAiCharacter(character),
    );
    final raw = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(raw['version'], 1);
    expect(raw['memory'], isNull);
    expect(raw['chatMessages'], isNull);
    expect(raw['apiKey'], isNull);
    expect(PeiFileService().parse(bytes).memory, isNull);
  });

  test('v1 files remain readable with missing optional fields', () {
    final raw = <String, dynamic>{
      'format': 'peilink.character',
      'version': 1,
      'character': {'name': '旧角色'},
      'configuration': <String, dynamic>{},
    };
    final package = PeiFileService().parse(
      Uint8List.fromList(utf8.encode(jsonEncode(raw))),
    );
    expect(package.version, 1);
    expect(package.memory, isNull);
    expect(package.character.characterName, '旧角色');
  });

  test(
    'v2 round trip preserves protected user history links and sources',
    () async {
      final character = _character('history');
      final storage = Memory2StorageService(characterId: character.id);
      final old = UserMemory(
        id: 'old',
        characterId: character.id,
        key: '饮品',
        value: '咖啡',
        status: UserMemoryStatus.superseded,
        supersededById: 'new',
        sourceMessageIds: const ['m1'],
        isPinned: true,
        userConfirmed: true,
      );
      final current = UserMemory(
        id: 'new',
        characterId: character.id,
        key: '饮品',
        value: '茶',
        mergedFromIds: const ['old'],
        sourceMessageIds: const ['m2'],
        userConfirmed: true,
      );
      await storage.saveUserMemories([old, current]);
      await storage.saveEventMemories([
        EventMemory(
          id: 'e',
          characterId: character.id,
          content: '纪念日',
          isPinned: true,
          sourceMessageIds: const ['m3'],
        ),
      ]);
      final service = PeiFileService();
      final bytes = await service.exportCharacter(
        character,
        CharacterSettings.genericDefaults(),
        includeMemories: true,
      );
      final imported = await service.importCharacter(service.parse(bytes));
      final target = Memory2StorageService(characterId: imported.character.id);
      final users = await target.loadUserMemories();
      expect(users.first.status, UserMemoryStatus.superseded);
      expect(users.first.supersededById, users.last.id);
      expect(users.last.mergedFromIds, [users.first.id]);
      expect(users.first.sourceMessageIds, ['m1']);
      expect(users.last.sourceMessageIds, ['m2']);
      expect(users.first.createdAt, old.createdAt);
      expect(users.first.userConfirmed && users.first.isPinned, isTrue);
      expect(users.last.userConfirmed, isTrue);
      expect((await target.loadEventMemories()).single.isPinned, isTrue);
      final sources = await MemorySourceResolver(
        characterId: imported.character.id,
      ).resolve(users.first.sourceMessageIds);
      expect(sources.single.available, isFalse);
      expect((await target.loadUserMemories()).length, 2);
      final payload = jsonDecode(utf8.decode(bytes)) as Map;
      expect(payload.containsKey('chatMessages'), isFalse);
      expect(payload.containsKey('images'), isFalse);
    },
  );

  test('new installation imports without an existing registry', () async {
    final character = _character('empty-install');
    final service = PeiFileService();
    final bytes = await service.exportCharacter(
      character,
      CharacterSettings.genericDefaults(),
    );
    final imported = await service.importCharacter(service.parse(bytes));
    expect(
      (await CharacterRegistryService().loadAllCharacters()).single.id,
      imported.character.id,
    );
  });

  test('damaged registry is never replaced by import', () async {
    final registry = File('${documents.path}/character_registry.json');
    await registry.writeAsString('{broken');
    final service = PeiFileService();
    final bytes = await service.exportCharacter(
      _character('safe'),
      CharacterSettings.genericDefaults(),
    );
    await expectLater(
      service.importCharacter(service.parse(bytes)),
      throwsA(isA<FormatException>()),
    );
    expect(await registry.readAsString(), '{broken');
    expect(await Directory('${documents.path}/characters').exists(), isFalse);
  });

  test(
    'duplicate alias survives edited target and export/import without remigration',
    () async {
      final character = _character('alias');
      final storage = Memory2StorageService(characterId: character.id);
      final event = _event(character.id, '共同参观过海洋馆');
      await storage.saveEventMemories([event]);
      final legacyFile = await CharacterScopeService(
        character.id,
      ).dataFile('memories.json');
      await legacyFile.writeAsString(
        jsonEncode([
          {'id': 'alias-old', 'content': event.content, 'category': '经历过的事'},
        ]),
      );
      final migration = LegacyMemoryMigrationService(characterId: character.id);
      expect((await migration.preview()).duplicates, 1);
      expect(
        (await migration.execute(await migration.preview())).success,
        isTrue,
      );
      await storage.saveEventMemories([
        EventMemory(
          id: event.id,
          characterId: character.id,
          content: '修正：参观的是水族馆',
          createdAt: event.createdAt,
          updatedAt: event.updatedAt,
        ),
      ]);
      final service = PeiFileService();
      final bytes = await service.exportCharacter(
        character,
        CharacterSettings.genericDefaults(),
        includeMemories: true,
      );
      final imported = await service.importCharacter(service.parse(bytes));
      final importedMigration = LegacyMemoryMigrationService(
        characterId: imported.character.id,
      );
      final importedStorage = Memory2StorageService(
        characterId: imported.character.id,
      );
      final events = await importedStorage.loadEventMemories();
      expect(events.single.legacySourceId, isNull);
      expect(
        await importedMigration.migratedSourceIds(events, []),
        contains('alias-old'),
      );
      expect((await importedMigration.preview()).transferable, 0);
      expect((await importedMigration.preview()).duplicates, 1);
    },
  );

  test(
    'unknown event extension metadata is rejected rather than silently lost',
    () {
      final memory = _minimalMemoryPayload();
      final event = _event('metadata', '保留边界').toJson();
      event['metadata'] = {'unknownRuntime': 'must-not-export'};
      memory['events'] = [event];
      expect(
        () => _parseMemory(memory),
        throwsA(isA<PeiFileCorruptedException>()),
      );
    },
  );

  test(
    'explicit v2 export round-trips all four portable memory groups',
    () async {
      final character = _character('source');
      final settings = CharacterSettings.fromAiCharacter(character);
      final event = _event(character.id, '共同去看蓝色绣球');
      final user = _user(character.id, '咖啡', '喜欢拿铁');
      final storage = Memory2StorageService(characterId: character.id);
      await storage.saveEventMemories([event]);
      await storage.saveUserMemories([user]);
      await storage.saveMemorySummary(
        const MemorySummary(
          characterId: 'source',
          generatedText: 'generated',
          userEditedText: 'edited',
          sourceRevision: 3,
        ),
      );
      final legacy = await CharacterScopeService(
        character.id,
      ).dataFile('memories.json');
      await legacy.writeAsString(
        jsonEncode([
          {'id': 'legacy-1', 'content': '旧记忆', 'category': '关于我'},
        ]),
      );

      final bytes = await PeiFileService().exportCharacter(
        character,
        settings,
        includeMemories: true,
      );
      final raw = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(raw['version'], 2);
      final memory = raw['memory'] as Map<String, dynamic>;
      expect(memory.keys.toSet(), {'legacy', 'events', 'users', 'summary'});
      final parsed = PeiFileService().parse(bytes);
      expect(parsed.memory!.legacy.single['content'], '旧记忆');
      expect(parsed.memory!.events.single.content, event.content);
      expect(parsed.memory!.users.single.value, user.value);
      expect(parsed.memory!.summary.userEditedText, 'edited');

      final registry = CharacterRegistryService();
      await registry.saveAllCharacters([character]);
      final imported = await PeiFileService(
        registry: registry,
      ).importCharacter(parsed);
      final importedLegacyFile = await CharacterScopeService(
        imported.character.id,
      ).dataFile('memories.json');
      final importedLegacy =
          jsonDecode(await importedLegacyFile.readAsString()) as List;
      final importedStorage = Memory2StorageService(
        characterId: imported.character.id,
      );
      expect(importedLegacy.single['content'], '旧记忆');
      expect(
        (await importedStorage.loadEventMemories()).single.content,
        event.content,
      );
      expect(
        (await importedStorage.loadUserMemories()).single.value,
        user.value,
      );
      expect(
        (await importedStorage.loadMemorySummary()).userEditedText,
        'edited',
      );
      final secondExport = await PeiFileService().exportCharacter(
        imported.character,
        CharacterSettings.fromAiCharacter(imported.character),
        includeMemories: true,
      );
      final second = PeiFileService().parse(secondExport);
      expect(second.memory!.legacy.single['content'], '旧记忆');
      expect(second.memory!.events.single.content, event.content);
      expect(second.memory!.users.single.value, user.value);
      expect(second.memory!.summary.userEditedText, 'edited');
    },
  );

  test(
    'v2 export carries only validated legacy-to-memory provenance links',
    () async {
      final character = _character('linked');
      final event = _event(character.id, '已迁移的共同经历');
      final eventWithSource = EventMemory(
        id: event.id,
        characterId: event.characterId,
        content: event.content,
        createdAt: event.createdAt,
        updatedAt: event.updatedAt,
        sourceType: MemorySourceType.legacy,
        legacySourceId: 'legacy-linked',
      );
      await Memory2StorageService(
        characterId: character.id,
      ).saveEventMemories([eventWithSource]);
      final legacy = await CharacterScopeService(
        character.id,
      ).dataFile('memories.json');
      await legacy.writeAsString(
        jsonEncode([
          {
            'id': 'legacy-linked',
            'content': event.content,
            'category': '经历过的事',
          },
        ]),
      );
      final journal = await CharacterScopeService(
        character.id,
      ).dataFile('legacy_memory_migration.json');
      await journal.writeAsString(
        jsonEncode({
          'version': 1,
          'links': {
            'legacy-linked': {'kind': 'event', 'id': event.id},
          },
        }),
      );
      final bytes = await PeiFileService().exportCharacter(
        character,
        CharacterSettings.fromAiCharacter(character),
        includeMemories: true,
      );
      final memory = (jsonDecode(utf8.decode(bytes)) as Map)['memory'] as Map;
      expect((memory['legacy'] as List).single['memory2Reference'], {
        'kind': 'event',
        'id': event.id,
      });
      expect(jsonEncode(memory), isNot(contains('legacy_memory_migration')));

      final registry = CharacterRegistryService();
      await registry.saveAllCharacters([character]);
      final imported = await PeiFileService(
        registry: registry,
      ).importCharacter(PeiFileService().parse(bytes));
      final importedLegacy = await CharacterScopeService(
        imported.character.id,
      ).dataFile('memories.json');
      final importedRows =
          jsonDecode(await importedLegacy.readAsString()) as List;
      expect(importedRows.single['memory2Reference'], isNull);
      final importedEvents = await Memory2StorageService(
        characterId: imported.character.id,
      ).loadEventMemories();
      expect(importedEvents.single.legacySourceId, 'legacy-linked');
    },
  );

  test(
    'portable provenance rejects a reference with the wrong target kind',
    () {
      final memory = _minimalMemoryPayload();
      final user = _user('x', 'k', 'v').toJson();
      memory['users'] = [user];
      memory['legacy'] = [
        {
          'id': 'legacy-1',
          'content': 'old',
          'memory2Reference': {'kind': 'event', 'id': user['id']},
        },
      ];
      expect(
        () => _parseMemory(memory),
        throwsA(isA<PeiFileCorruptedException>()),
      );
    },
  );

  test('dangling legacy memory2 references are rejected', () {
    final memory = _minimalMemoryPayload();
    memory['legacy'] = [
      {
        'id': 'legacy-1',
        'content': 'old',
        'category': '经历过的事',
        'memory2Reference': {'kind': 'event', 'id': 'missing'},
      },
    ];
    expect(
      () => _parseMemory(memory),
      throwsA(isA<PeiFileCorruptedException>()),
    );
  });

  test('v2 import keeps memory isolated under the new character id', () async {
    final source = _character('source');
    final event = _event(source.id, '源角色的共同经历');
    await Memory2StorageService(
      characterId: source.id,
    ).saveEventMemories([event]);
    final bytes = await PeiFileService().exportCharacter(
      source,
      CharacterSettings.fromAiCharacter(source),
      includeMemories: true,
    );
    final registry = CharacterRegistryService();
    await registry.saveAllCharacters([source]);
    final result = await PeiFileService(
      registry: registry,
    ).importCharacter(PeiFileService().parse(bytes));
    final imported = await Memory2StorageService(
      characterId: result.character.id,
    ).loadEventMemories();
    final original = await Memory2StorageService(
      characterId: source.id,
    ).loadEventMemories();
    expect(imported.single.characterId, result.character.id);
    expect(imported.single.content, event.content);
    expect(original.single.characterId, source.id);
    expect(result.character.id, isNot(source.id));
  });

  test(
    'portable payload excludes runtime, provider, chat, archive and cursor data',
    () async {
      final character = _character('portable');
      await CharacterScopeService(character.id)
          .dataFile('extraction_cursor.json')
          .then(
            (file) => file.writeAsString('{"cursor":99,"diagnostic":"secret"}'),
          );
      await CharacterScopeService(character.id)
          .dataFile('chat_messages.json')
          .then((file) => file.writeAsString('[{"content":"chat sentinel"}]'));
      await CharacterScopeService(character.id)
          .dataFile('archive.json')
          .then(
            (file) => file.writeAsString('[{"content":"archive sentinel"}]'),
          );
      final bytes = await PeiFileService().exportCharacter(
        character,
        CharacterSettings.fromAiCharacter(character),
        includeMemories: true,
      );
      final raw = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final memory = raw['memory'] as Map<String, dynamic>;
      expect(memory.keys.toSet(), {'legacy', 'events', 'users', 'summary'});
      final encoded = jsonEncode(raw);
      for (final forbidden in [
        'cursor',
        'diagnostic',
        'chat',
        'archive',
        'apiKey',
        'provider',
        'extractionState',
      ]) {
        expect(encoded.toLowerCase(), isNot(contains(forbidden.toLowerCase())));
      }
    },
  );

  test('corrupt memory is rejected before import creates a role', () async {
    final character = _character('corrupt');
    final bytes = await PeiFileService().exportCharacter(
      character,
      CharacterSettings.fromAiCharacter(character),
    );
    final raw = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    raw['version'] = 2;
    raw['memory'] = _minimalMemoryPayload();
    (raw['memory'] as Map)['events'] = [
      {'id': 'duplicate'},
      {'id': 'duplicate'},
    ];
    expect(
      () => PeiFileService().parse(
        Uint8List.fromList(utf8.encode(jsonEncode(raw))),
      ),
      throwsA(isA<PeiFileCorruptedException>()),
    );
    expect(await CharacterRegistryService().loadAllCharacters(), isEmpty);
  });

  test('duplicate ids and wrong memory field types are rejected', () {
    final base = _minimalMemoryPayload();
    final duplicate = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    final duplicateEvent = _event('x', 'a').toJson();
    duplicateEvent['id'] = 'same-id';
    final duplicateEvent2 = _event('x', 'b').toJson();
    duplicateEvent2['id'] = 'same-id';
    duplicate['events'] = [duplicateEvent, duplicateEvent2];
    expect(
      () => _parseMemory(duplicate),
      throwsA(isA<PeiFileCorruptedException>()),
    );
    final wrong = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    wrong['users'] = 'not-a-list';
    expect(
      () => _parseMemory(wrong),
      throwsA(isA<PeiFileCorruptedException>()),
    );
  });

  test(
    'registry failure rolls back the newly imported role directory',
    () async {
      final source = _character('rollback');
      final bytes = await PeiFileService().exportCharacter(
        source,
        CharacterSettings.fromAiCharacter(source),
        includeMemories: true,
      );
      final registry = _FailingRegistry();
      await File(
        '${documents.path}/character_registry.json',
      ).writeAsString('[]');
      await expectLater(
        PeiFileService(
          registry: registry,
        ).importCharacter(PeiFileService().parse(bytes)),
        throwsA(isA<StateError>()),
      );
      expect(await registry.loadAllCharacters(), isEmpty);
      expect(registry.attemptedId, isNotNull);
      final importedDirectory = Directory(
        '${documents.path}/characters/${registry.attemptedId}',
      );
      expect(await importedDirectory.exists(), isFalse);
    },
  );
}

AiCharacter _character(String id) => AiCharacter(
  id: id,
  characterName: '角色$id',
  remark: '',
  createdAt: DateTime(2026, 1, 1),
);

EventMemory _event(String characterId, String content) => EventMemory(
  id: 'event-$characterId-${content.hashCode}',
  characterId: characterId,
  content: content,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  sourceType: MemorySourceType.manual,
);

UserMemory _user(String characterId, String key, String value) => UserMemory(
  id: 'user-$characterId',
  characterId: characterId,
  key: key,
  value: value,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  sourceType: MemorySourceType.manual,
);

Map<String, dynamic> _minimalMemoryPayload() => {
  'legacy': <Map<String, dynamic>>[],
  'events': <Map<String, dynamic>>[],
  'users': <Map<String, dynamic>>[],
  'summary': const MemorySummary(characterId: 'x').toJson(),
};

void _parseMemory(Map<String, dynamic> memory) {
  final wrapper = <String, dynamic>{
    'format': 'peilink.character',
    'version': 2,
    'character': {'name': 'x'},
    'configuration': <String, dynamic>{},
    'memory': memory,
  };
  PeiFileService().parse(Uint8List.fromList(utf8.encode(jsonEncode(wrapper))));
}

class _FailingRegistry extends CharacterRegistryService {
  String? attemptedId;

  @override
  Future<void> addCharacter(AiCharacter character) async {
    attemptedId = character.id;
    throw StateError('registry write failed');
  }
}
