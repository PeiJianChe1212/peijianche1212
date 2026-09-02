import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_archive.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/legacy_memory_view.dart';
import 'package:peijianche_app/models/memory_item.dart';
import 'package:peijianche_app/models/memory_source_type.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/services/legacy_memory_adapter.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('memory2_foundation_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Memory2StorageService storage(String characterId) {
    return Memory2StorageService(
      characterId: characterId,
      fileProvider: (id, fileName) async =>
          File('${directory.path}/$id/$fileName'),
    );
  }

  EventMemory event(String id, String characterId, {bool pinned = false}) {
    return EventMemory(
      id: id,
      characterId: characterId,
      content: '共同经历 $id',
      occurredAt: DateTime.utc(2026, 8, 1),
      createdAt: DateTime.utc(2026, 8, 2),
      updatedAt: DateTime.utc(2026, 8, 3),
      status: EventMemoryStatus.fading,
      recallCount: 2,
      isPinned: pinned,
      sourceType: MemorySourceType.automatic,
      sourceMessageIds: const ['message-1'],
      metadata: const {'place': '海边'},
    );
  }

  UserMemory user(String id, String characterId) {
    return UserMemory(
      id: id,
      characterId: characterId,
      key: '喜欢的饮品',
      value: '咖啡',
      createdAt: DateTime.utc(2026, 8, 2),
      updatedAt: DateTime.utc(2026, 8, 3),
      status: UserMemoryStatus.superseded,
      supersededById: 'user-new',
      mergedFromIds: const ['user-old'],
      isPinned: true,
      userConfirmed: true,
      sourceType: MemorySourceType.automatic,
      sourceMessageIds: const ['message-2'],
      legacySourceId: 'legacy-user',
    );
  }

  test(
    'Event/User/Summary round-trip preserves fields and effective summary',
    () {
      final eventValue = event('event-1', 'role-a', pinned: true);
      final userValue = user('user-1', 'role-a');
      final summary = MemorySummary(
        characterId: 'role-a',
        generatedText: '系统生成总结',
        userEditedText: '用户确认后的总结',
        generatedAt: DateTime.utc(2026, 8, 4),
        editedAt: DateTime.utc(2026, 8, 5),
        sourceRevision: 3,
      );

      final restoredEvent = EventMemory.fromJson(eventValue.toJson());
      final restoredUser = UserMemory.fromJson(userValue.toJson());
      final restoredSummary = MemorySummary.fromJson(summary.toJson());

      expect(restoredEvent.toJson(), eventValue.toJson());
      expect(restoredUser.toJson(), userValue.toJson());
      expect(restoredSummary.toJson(), summary.toJson());
      expect(restoredSummary.effectiveText, '用户确认后的总结');
    },
  );

  test(
    'missing fields use safe defaults and unknown statuses fall back to active',
    () {
      final eventValue = EventMemory.fromJson({
        'id': 'event-default',
        'characterId': 'role-a',
        'content': '内容',
        'status': 'not-a-real-status',
      });
      final userValue = UserMemory.fromJson({
        'id': 'user-default',
        'characterId': 'role-a',
        'key': '偏好',
        'value': '茶',
        'status': 'not-a-real-status',
      });
      final summary = MemorySummary.fromJson({'characterId': 'role-a'});

      expect(eventValue.status, EventMemoryStatus.active);
      expect(eventValue.occurredAt, isNull);
      expect(eventValue.recallCount, 0);
      expect(eventValue.isPinned, isFalse);
      expect(userValue.status, UserMemoryStatus.active);
      expect(userValue.mergedFromIds, isEmpty);
      expect(userValue.userConfirmed, isFalse);
      expect(summary.generatedText, isEmpty);
      expect(summary.userEditedText, isEmpty);
      expect(summary.sourceRevision, 0);
    },
  );

  test('empty, missing, and corrupt files load as empty safe values', () async {
    final service = storage('role-a');

    expect(await service.loadEventMemories(), isEmpty);
    expect(await service.loadUserMemories(), isEmpty);
    expect((await service.loadMemorySummary()).effectiveText, isEmpty);

    final eventFile = File(
      '${directory.path}/role-a/${Memory2StorageService.eventFileName}',
    )..parent.createSync(recursive: true);
    await eventFile.writeAsString('{broken');
    final userFile = File(
      '${directory.path}/role-a/${Memory2StorageService.userFileName}',
    );
    await userFile.writeAsString('');
    final summaryFile = File(
      '${directory.path}/role-a/${Memory2StorageService.summaryFileName}',
    );
    await summaryFile.writeAsString(jsonEncode({'schemaVersion': 999}));

    expect(await service.loadEventMemories(), isEmpty);
    expect(await service.loadUserMemories(), isEmpty);
    expect((await service.loadMemorySummary()).characterId, 'role-a');
  });

  test('Event and User upsert replaces by id and delete removes by id', () async {
    final service = storage('role-a');
    await service.upsertEventMemory(event('event-1', 'other-role'));
    await service.upsertEventMemory(
      EventMemory(id: 'event-1', characterId: 'role-a', content: '更新后的经历'),
    );
    await service.upsertUserMemory(user('user-1', 'other-role'));
    await service.upsertUserMemory(
      UserMemory(id: 'user-1', characterId: 'role-a', key: '姓名', value: '小满'),
    );

    expect((await service.loadEventMemories()).single.content, '更新后的经历');
    expect((await service.loadUserMemories()).single.displayText, '姓名：小满');
    final eventWrapper =
        jsonDecode(
              await File(
                '${directory.path}/role-a/${Memory2StorageService.eventFileName}',
              ).readAsString(),
            )
            as Map;
    final userWrapper =
        jsonDecode(
              await File(
                '${directory.path}/role-a/${Memory2StorageService.userFileName}',
              ).readAsString(),
            )
            as Map;
    expect(eventWrapper['schemaVersion'], Memory2StorageService.schemaVersion);
    expect(userWrapper['schemaVersion'], Memory2StorageService.schemaVersion);

    await service.deleteEventMemory('event-1');
    await service.deleteUserMemory('user-1');
    expect(await service.loadEventMemories(), isEmpty);
    expect(await service.loadUserMemories(), isEmpty);
  });

  test(
    'Summary saves with schema wrapper and userEditedText takes precedence',
    () async {
      final service = storage('role-a');
      await service.saveMemorySummary(
        MemorySummary(
          characterId: 'other-role',
          generatedText: 'generated',
          userEditedText: 'edited',
          sourceRevision: 4,
        ),
      );

      final file = File(
        '${directory.path}/role-a/${Memory2StorageService.summaryFileName}',
      );
      final raw = jsonDecode(await file.readAsString()) as Map;
      expect(raw['schemaVersion'], Memory2StorageService.schemaVersion);
      expect((raw['summary'] as Map)['characterId'], 'role-a');
      final restored = await service.loadMemorySummary();
      expect(restored.effectiveText, 'edited');
      expect(restored.sourceRevision, 4);
    },
  );

  test(
    'two characters remain isolated and service scopes incoming objects',
    () async {
      await storage('role-a').upsertEventMemory(event('same-id', 'role-b'));
      await storage('role-b').upsertUserMemory(user('same-id', 'role-a'));

      final eventsA = await storage('role-a').loadEventMemories();
      final usersB = await storage('role-b').loadUserMemories();
      expect(eventsA.single.characterId, 'role-a');
      expect(usersB.single.characterId, 'role-b');
      expect(await storage('role-b').loadEventMemories(), isEmpty);
      expect(await storage('role-a').loadUserMemories(), isEmpty);
    },
  );

  test(
    'legacy adapter maps event, user, and unknown categories read-only',
    () async {
      final legacy = <MemoryItem>[
        MemoryItem(
          id: 'legacy-event',
          content: '一起看过海',
          category: '经历过的事',
          isPinned: true,
          isArchived: true,
        ),
        MemoryItem(id: 'legacy-user', content: '喜欢咖啡', category: '关于我'),
        MemoryItem(id: 'legacy-unknown', content: '旧分类', category: '未分类'),
      ];
      final views = await LegacyMemoryAdapter(
        characterId: 'role-a',
        loader: () async => legacy,
      ).loadReadOnlyViews();

      expect(views.map((item) => item.kind), [
        LegacyMemoryKind.event,
        LegacyMemoryKind.user,
        LegacyMemoryKind.legacyUnclassified,
      ]);
      expect(views.first.isPinned, isTrue);
      expect(views.first.legacyArchived, isTrue);
      expect(views.first.occurredAt, isNull);
    },
  );

  test(
    'new service does not write legacy memories or change Archive',
    () async {
      final legacyFile = File('${directory.path}/role-a/memories.json')
        ..parent.createSync(recursive: true);
      const legacyJson = '[{"id":"old","content":"旧记忆","category":"经历过的事"}]';
      await legacyFile.writeAsString(legacyJson);
      final archiveFile = File(
        '${directory.path}/role-a/character_archive.json',
      );
      const archiveJson = '{"characterId":"role-a","values":{"likes":"咖啡"}}';
      await archiveFile.writeAsString(archiveJson);

      final service = storage('role-a');
      await service.upsertEventMemory(event('new-event', 'role-a'));
      await service.upsertUserMemory(user('new-user', 'role-a'));
      await service.saveMemorySummary(
        const MemorySummary(characterId: 'role-a', generatedText: 'summary'),
      );

      expect(await legacyFile.readAsString(), legacyJson);
      expect(await archiveFile.readAsString(), archiveJson);
      expect(
        await File('${directory.path}/role-a/memories.json').exists(),
        isTrue,
      );
      expect(
        await File('${directory.path}/role-a/character_archive.json').exists(),
        isTrue,
      );
      final archive = CharacterArchive.fromJson(
        jsonDecode(await archiveFile.readAsString()),
        'role-a',
      );
      expect(archive.value('likes'), '咖啡');
    },
  );
}
