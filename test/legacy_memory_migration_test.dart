import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/memory_source_type.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/services/legacy_memory_migration_service.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';

class _FailingUserStorage extends Memory2StorageService {
  _FailingUserStorage(String id, Memory2FileProvider provider)
    : super(characterId: id, fileProvider: provider);
  bool failNext = true;

  @override
  Future<void> saveUserMemories(List<UserMemory> items) {
    if (failNext) {
      failNext = false;
      throw Exception('injected user save failure');
    }
    return super.saveUserMemories(items);
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('legacy_migration_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> fileFor(String id, String name) async {
    final file = File('${root.path}/$id/$name');
    await file.parent.create(recursive: true);
    return file;
  }

  Memory2StorageService storage(String id) =>
      Memory2StorageService(characterId: id, fileProvider: fileFor);

  Future<void> writeLegacy(String id, List<Map<String, dynamic>> items) async {
    final file = await fileFor(id, 'memories.json');
    await file.writeAsString(jsonEncode(items), flush: true);
  }

  Map<String, dynamic> legacy({
    String? id,
    required String content,
    required String category,
    bool pinned = false,
    bool archived = false,
    String? createdAt,
  }) => {
    'id': ?id,
    'content': content,
    'category': category,
    'isPinned': pinned,
    'isArchived': archived,
    'createdAt': ?createdAt,
  };

  test(
    'preview classifies transferable, duplicate, archived, invalid and unclassified',
    () async {
      await writeLegacy('role-a', [
        legacy(id: 'event-1', content: '一起去过海边', category: '经历过的事'),
        legacy(id: 'user-1', content: '喜欢咖啡', category: '关于我'),
        legacy(id: 'unknown', content: '旧分类', category: '其他'),
        legacy(
          id: 'archived',
          content: '旧归档',
          category: '经历过的事',
          archived: true,
        ),
        {'content': ''},
        {'category': '关于我'},
      ]);
      final preview = await LegacyMemoryMigrationService(
        characterId: 'role-a',
        storage: storage('role-a'),
        fileProvider: fileFor,
      ).preview();

      expect(preview.events, 1);
      expect(preview.users, 1);
      expect(preview.transferable, 2);
      expect(preview.unclassified, 1);
      expect(preview.archived, 1);
      expect(preview.invalid, 2);
    },
  );

  test(
    'execute preserves legacy bytes, links source ids, and maps fields safely',
    () async {
      final created = '2026-08-20T00:00:00.000Z';
      await writeLegacy('role-a', [
        legacy(
          id: 'event-1',
          content: '一起去过海边',
          category: '经历过的事',
          pinned: true,
          createdAt: created,
        ),
        legacy(
          id: 'user-1',
          content: '喜欢咖啡',
          category: '关于我',
          createdAt: created,
        ),
      ]);
      final legacyFile = await fileFor('role-a', 'memories.json');
      final before = await legacyFile.readAsBytes();
      final service = LegacyMemoryMigrationService(
        characterId: 'role-a',
        storage: storage('role-a'),
        fileProvider: fileFor,
      );
      final preview = await service.preview();
      final result = await service.execute(preview);
      expect(result.success, isTrue);
      expect(await legacyFile.readAsBytes(), before);

      final events = await storage('role-a').loadEventMemoriesStrict();
      final users = await storage('role-a').loadUserMemoriesStrict();
      expect(events.single.legacySourceId, 'event-1');
      expect(events.single.sourceType, MemorySourceType.legacy);
      expect(events.single.isPinned, isTrue);
      expect(events.single.createdAt, DateTime.parse(created));
      expect(users.single.legacySourceId, 'user-1');
      expect(users.single.sourceType, MemorySourceType.legacy);
      expect(
        await service.migratedSourceIds(events, users),
        containsAll(['event-1', 'user-1']),
      );
    },
  );

  test(
    'missing ids are deterministic and repeated content is counted as duplicate',
    () async {
      final item = legacy(content: '无 ID 的经历', category: '经历过的事');
      await writeLegacy('role-a', [item]);
      final service = LegacyMemoryMigrationService(
        characterId: 'role-a',
        storage: storage('role-a'),
        fileProvider: fileFor,
      );
      final first = await service.preview();
      final second = await service.preview();
      expect(first.revision, second.revision);
      final result = await service.execute(first);
      expect(result.success, isTrue);
      final after = await service.preview();
      expect(after.transferable, 0);
      expect(after.duplicates, 1);
      expect(after.revision, isNotEmpty);
    },
  );

  test('duplicate or empty plans do not add another Memory2 record', () async {
    await writeLegacy('role-a', [
      legacy(id: 'event-1', content: '共同经历', category: '经历过的事'),
    ]);
    final service = LegacyMemoryMigrationService(
      characterId: 'role-a',
      storage: storage('role-a'),
      fileProvider: fileFor,
    );
    final preview = await service.preview();
    expect((await service.execute(preview)).success, isTrue);
    final duplicate = await service.preview();
    expect(duplicate.transferable, 0);
    expect((await service.execute(duplicate)).success, isTrue);
    expect((await storage('role-a').loadEventMemoriesStrict()), hasLength(1));
  });

  test('corrupt legacy JSON is rejected without writes', () async {
    final file = await fileFor('role-a', 'memories.json');
    const bytes = '{not-json';
    await file.writeAsString(bytes, flush: true);
    final service = LegacyMemoryMigrationService(
      characterId: 'role-a',
      storage: storage('role-a'),
      fileProvider: fileFor,
    );
    expect(service.preview, throwsA(isA<FormatException>()));
    expect(await file.readAsString(), bytes);
    expect(
      await File('${root.path}/role-a/event_memories.json').exists(),
      isFalse,
    );
  });

  test(
    'character scopes are isolated and confirmed users are not overwritten',
    () async {
      await writeLegacy('role-a', [
        legacy(id: 'u', content: '喜欢茶', category: '关于我'),
      ]);
      await writeLegacy('role-b', [
        legacy(id: 'u', content: '喜欢咖啡', category: '关于我'),
      ]);
      await storage('role-a').saveUserMemories([
        UserMemory(
          id: 'existing',
          characterId: 'role-a',
          key: '',
          value: '喜欢茶',
          userConfirmed: true,
        ),
      ]);
      final a = LegacyMemoryMigrationService(
        characterId: 'role-a',
        storage: storage('role-a'),
        fileProvider: fileFor,
      );
      final b = LegacyMemoryMigrationService(
        characterId: 'role-b',
        storage: storage('role-b'),
        fileProvider: fileFor,
      );
      expect((await a.preview()).transferable, 0);
      expect((await b.preview()).transferable, 1);
      expect((await a.execute(await a.preview())).success, isTrue);
      expect((await b.execute(await b.preview())).success, isTrue);
      expect(
        (await storage('role-a').loadUserMemoriesStrict()).single.id,
        'existing',
      );
      expect(
        (await storage('role-b').loadUserMemoriesStrict()).single.characterId,
        'role-b',
      );
    },
  );

  test(
    'migration and ordinary same-role upsert do not lose either write',
    () async {
      await writeLegacy('role-a', [
        legacy(id: 'old', content: '迁移事件', category: '经历过的事'),
      ]);
      final service = LegacyMemoryMigrationService(
        characterId: 'role-a',
        fileProvider: fileFor,
      );
      final preview = await service.preview();
      await Future.wait([
        service.execute(preview),
        storage('role-a').upsertEventMemory(
          EventMemory(id: 'ui', characterId: 'role-a', content: '用户手工事件'),
        ),
      ]);
      expect(
        (await storage(
          'role-a',
        ).loadEventMemoriesStrict()).map((e) => e.content),
        containsAll(['迁移事件', '用户手工事件']),
      );
    },
  );

  test('migration does not create recall history', () async {
    await writeLegacy('role-a', [
      legacy(id: 'e', content: '经历', category: '经历过的事'),
    ]);
    final service = LegacyMemoryMigrationService(
      characterId: 'role-a',
      storage: storage('role-a'),
      fileProvider: fileFor,
    );
    await service.execute(await service.preview());
    final event = (await storage('role-a').loadEventMemoriesStrict()).single;
    expect(event.recallCount, 0);
    expect(event.lastRecalledAt, isNull);
    expect(event.occurredAt, isNull);
    expect(event.sourceMessageIds, isEmpty);
  });

  test(
    'ambiguous same source id is kept in legacy instead of guessing',
    () async {
      await writeLegacy('role-a', [
        legacy(id: 'collision', content: '不同经历', category: '经历过的事'),
        legacy(id: 'collision', content: '不同偏好', category: '关于我'),
      ]);
      final service = LegacyMemoryMigrationService(
        characterId: 'role-a',
        fileProvider: fileFor,
      );
      final preview = await service.preview();
      expect(preview.invalid, 2);
      expect(preview.transferable, 0);
    },
  );

  test(
    'generated id collision preserves existing event and allocates unique id',
    () async {
      final id = 'legacy_event_${base64Url.encode(utf8.encode('e'))}';
      await storage('role-a').saveEventMemories([
        EventMemory(id: id, characterId: 'role-a', content: '无关现有事件'),
      ]);
      await writeLegacy('role-a', [
        legacy(id: 'e', content: '真正旧经历', category: '经历过的事'),
      ]);
      final service = LegacyMemoryMigrationService(
        characterId: 'role-a',
        fileProvider: fileFor,
      );
      expect((await service.execute(await service.preview())).success, isTrue);
      final items = await storage('role-a').loadEventMemoriesStrict();
      expect(items.map((e) => e.id).toSet(), hasLength(2));
      expect(items.first.content, '无关现有事件');
      expect((await service.preview()).duplicates, 1);
    },
  );

  test(
    'same value under a different user key is not silently merged',
    () async {
      await storage('role-a').saveUserMemories([
        UserMemory(
          id: 'keyed',
          characterId: 'role-a',
          key: '饮品',
          value: '喜欢茶',
          userConfirmed: true,
          isPinned: true,
        ),
      ]);
      await writeLegacy('role-a', [
        legacy(id: 'u', content: '喜欢茶', category: '关于我'),
      ]);
      final service = LegacyMemoryMigrationService(
        characterId: 'role-a',
        fileProvider: fileFor,
      );
      expect((await service.preview()).users, 1);
      await service.execute(await service.preview());
      final users = await storage('role-a').loadUserMemoriesStrict();
      expect(users, hasLength(2));
      expect(users.first.userConfirmed, isTrue);
      expect(users.first.isPinned, isTrue);
      expect(users.last.userConfirmed, isFalse);
    },
  );

  test('stale preview is rejected after legacy content changes', () async {
    await writeLegacy('role-a', [
      legacy(id: 'e', content: '旧经历', category: '经历过的事'),
    ]);
    final service = LegacyMemoryMigrationService(
      characterId: 'role-a',
      storage: storage('role-a'),
      fileProvider: fileFor,
    );
    final preview = await service.preview();
    await writeLegacy('role-a', [
      legacy(id: 'e', content: '改过的经历', category: '经历过的事'),
    ]);
    final result = await service.execute(preview);
    expect(result.success, isFalse);
    expect(result.error, contains('重新预览'));
    expect((await storage('role-a').loadEventMemories()), isEmpty);
  });

  test('preview alone is cancel-safe and creates no migration files', () async {
    await writeLegacy('role-a', [
      legacy(id: 'e', content: '只预览', category: '经历过的事'),
    ]);
    final service = LegacyMemoryMigrationService(
      characterId: 'role-a',
      storage: storage('role-a'),
      fileProvider: fileFor,
    );
    final preview = await service.preview();
    expect(preview.transferable, 1);
    for (final name in [
      'event_memories.json',
      'user_memories.json',
      LegacyMemoryMigrationService.ledgerFile,
    ]) {
      expect(
        await File('${root.path}/role-a/$name').exists(),
        isFalse,
        reason: name,
      );
    }
  });

  test(
    'partial save failure can retry without duplicating already saved events',
    () async {
      await writeLegacy('role-a', [
        legacy(id: 'e', content: '失败前的经历', category: '经历过的事'),
        legacy(id: 'u', content: '失败前的偏好', category: '关于我'),
      ]);
      final failing = _FailingUserStorage('role-a', fileFor);
      final service = LegacyMemoryMigrationService(
        characterId: 'role-a',
        storage: failing,
        fileProvider: fileFor,
      );
      final preview = await service.preview();
      expect((await service.execute(preview)).success, isFalse);
      expect((await failing.loadEventMemoriesStrict()), hasLength(1));
      final retryPreview = await service.preview();
      expect(retryPreview.transferable, 1);
      expect((await service.execute(retryPreview)).success, isTrue);
      expect((await failing.loadEventMemoriesStrict()), hasLength(1));
      expect((await failing.loadUserMemoriesStrict()), hasLength(1));
    },
  );

  test(
    'same-role concurrent execution is serialized and does not duplicate',
    () async {
      await writeLegacy('role-a', [
        legacy(id: 'e', content: '并发经历', category: '经历过的事'),
      ]);
      final service = LegacyMemoryMigrationService(
        characterId: 'role-a',
        storage: storage('role-a'),
        fileProvider: fileFor,
      );
      final preview = await service.preview();
      final results = await Future.wait([
        service.execute(preview),
        service.execute(preview),
      ]);
      expect(results.where((result) => result.success), hasLength(1));
      expect((await storage('role-a').loadEventMemoriesStrict()), hasLength(1));
    },
  );

  test(
    'normalized duplicate is conservative: whitespace differs, punctuation does not',
    () async {
      await writeLegacy('role-a', [
        legacy(id: 'same', content: '喜欢   咖啡', category: '关于我'),
        legacy(id: 'same-space', content: '  喜欢 咖啡  ', category: '关于我'),
        legacy(id: 'punctuation', content: '喜欢咖啡。', category: '关于我'),
      ]);
      final service = LegacyMemoryMigrationService(
        characterId: 'role-a',
        storage: storage('role-a'),
        fileProvider: fileFor,
      );
      expect((await service.preview()).users, 2);
      expect((await service.preview()).duplicates, 1);
      await service.execute(await service.preview());
      expect((await storage('role-a').loadUserMemoriesStrict()), hasLength(2));
    },
  );

  test(
    'corrupt Memory2 file aborts preview and does not overwrite legacy',
    () async {
      await writeLegacy('role-a', [
        legacy(id: 'e', content: '不要覆盖', category: '经历过的事'),
      ]);
      final legacyFile = await fileFor('role-a', 'memories.json');
      final before = await legacyFile.readAsBytes();
      final eventFile = await fileFor(
        'role-a',
        Memory2StorageService.eventFileName,
      );
      await eventFile.writeAsString(
        '{"schemaVersion":999,"items":[]}',
        flush: true,
      );
      final service = LegacyMemoryMigrationService(
        characterId: 'role-a',
        storage: storage('role-a'),
        fileProvider: fileFor,
      );
      expect(service.preview, throwsA(isA<FormatException>()));
      expect(await legacyFile.readAsBytes(), before);
      expect(
        await eventFile.readAsString(),
        '{"schemaVersion":999,"items":[]}',
      );
    },
  );
}
