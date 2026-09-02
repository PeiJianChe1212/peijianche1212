import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_archive.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/memory_extraction_result.dart';
import 'package:peijianche_app/models/memory_source_type.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/services/event_memory_lifecycle_service.dart';
import 'package:peijianche_app/services/memory2_engine.dart';
import 'package:peijianche_app/services/memory2_mutation_coordinator.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('event_lifecycle_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Memory2StorageService storage(String characterId) => Memory2StorageService(
    characterId: characterId,
    fileProvider: (id, fileName) async =>
        File('${directory.path}/$id/$fileName'),
  );

  EventMemory memory(
    String id,
    DateTime createdAt, {
    EventMemoryStatus status = EventMemoryStatus.active,
    DateTime? lastRecalledAt,
    int recallCount = 0,
    bool pinned = false,
    String content = '一起看海',
  }) {
    return EventMemory(
      id: id,
      characterId: 'role-a',
      content: content,
      occurredAt: DateTime.utc(2026, 1, 1),
      createdAt: createdAt,
      updatedAt: createdAt,
      sourceMessageIds: const ['source-a'],
      status: status,
      lastRecalledAt: lastRecalledAt,
      recallCount: recallCount,
      isPinned: pinned,
      sourceType: MemorySourceType.automatic,
    );
  }

  test(
    'evaluateStatus follows 30-day lifecycle boundaries and recall extension',
    () {
      final service = EventMemoryLifecycleService(
        storage: storage('role-a'),
        characterId: 'role-a',
      );
      final created = DateTime.utc(2026, 1, 1);

      expect(
        service.evaluateStatus(memory('a', created), created),
        EventMemoryStatus.active,
      );
      expect(
        service.evaluateStatus(
          memory('a', created),
          created.add(const Duration(days: 29)),
        ),
        EventMemoryStatus.active,
      );
      expect(
        service.evaluateStatus(
          memory('a', created),
          created.add(const Duration(days: 30)),
        ),
        EventMemoryStatus.fading,
      );
      expect(
        service.evaluateStatus(
          memory('a', created),
          created.add(const Duration(days: 59)),
        ),
        EventMemoryStatus.fading,
      );
      expect(
        service.evaluateStatus(
          memory('a', created),
          created.add(const Duration(days: 60)),
        ),
        EventMemoryStatus.pendingForget,
      );
      expect(
        service.evaluateStatus(
          memory('a', created),
          created.add(const Duration(days: 89)),
        ),
        EventMemoryStatus.pendingForget,
      );
      expect(
        service.evaluateStatus(
          memory('a', created),
          created.add(const Duration(days: 90)),
        ),
        EventMemoryStatus.forgotten,
      );
      expect(
        service.evaluateStatus(
          memory(
            'a',
            created,
            lastRecalledAt: created.add(const Duration(days: 20)),
            recallCount: 10,
          ),
          created.add(const Duration(days: 79)),
        ),
        EventMemoryStatus.active,
      );
      expect(
        service.evaluateStatus(
          memory('pinned', created, pinned: true),
          created.add(const Duration(days: 1000)),
        ),
        EventMemoryStatus.active,
      );
    },
  );

  test(
    'refresh persists statuses without physically deleting memories',
    () async {
      final service = storage('role-a');
      await service.saveEventMemories([
        memory('active', DateTime.utc(2026, 3, 15)),
        memory(
          'fading',
          DateTime.utc(2026, 2, 15),
          status: EventMemoryStatus.active,
        ),
        memory(
          'pending',
          DateTime.utc(2026, 1, 31),
          status: EventMemoryStatus.active,
        ),
        memory(
          'forgotten',
          DateTime.utc(2026, 1, 1),
          status: EventMemoryStatus.active,
        ),
      ]);
      final lifecycle = EventMemoryLifecycleService(
        characterId: 'role-a',
        storage: service,
      );
      final changed = await lifecycle.refresh(now: DateTime.utc(2026, 4, 1));

      expect(changed, 3);
      final restored = await service.loadEventMemories();
      expect(restored, hasLength(4));
      expect(
        restored.firstWhere((item) => item.id == 'fading').status,
        EventMemoryStatus.fading,
      );
      expect(
        restored.firstWhere((item) => item.id == 'pending').status,
        EventMemoryStatus.pendingForget,
      );
      expect(
        restored.firstWhere((item) => item.id == 'forgotten').status,
        EventMemoryStatus.forgotten,
      );
      expect(restored.map((item) => item.id), contains('forgotten'));
      final snapshot = await File(
        '${directory.path}/role-a/${Memory2StorageService.eventFileName}',
      ).readAsString();
      expect(await lifecycle.refresh(now: DateTime.utc(2026, 4, 1)), 0);
      expect(
        await File(
          '${directory.path}/role-a/${Memory2StorageService.eventFileName}',
        ).readAsString(),
        snapshot,
      );
    },
  );

  test(
    'recall extends active state, preserves body/source, and is idempotent only by call semantics',
    () async {
      final service = storage('role-a');
      final created = DateTime.utc(2026, 1, 1);
      await service.saveEventMemories([
        memory('recallable', created, status: EventMemoryStatus.fading),
      ]);
      final lifecycle = EventMemoryLifecycleService(
        characterId: 'role-a',
        storage: service,
      );
      final recalledAt = DateTime.utc(2026, 2, 10);
      expect(
        await lifecycle.markRecalled('recallable', now: recalledAt),
        isTrue,
      );
      final restored = (await service.loadEventMemories()).single;
      expect(restored.status, EventMemoryStatus.active);
      expect(restored.lastRecalledAt, recalledAt);
      expect(restored.recallCount, 1);
      expect(restored.content, '一起看海');
      expect(restored.sourceMessageIds, ['source-a']);
      expect(await lifecycle.markRecalled('missing', now: recalledAt), isFalse);
    },
  );

  test(
    'markRecalled does not revive forgotten; restore explicitly revives at now',
    () async {
      final service = storage('role-a');
      final created = DateTime.utc(2026, 1, 1);
      await service.saveEventMemories([
        memory('forgotten', created, status: EventMemoryStatus.forgotten),
      ]);
      final lifecycle = EventMemoryLifecycleService(
        characterId: 'role-a',
        storage: service,
      );
      final now = DateTime.utc(2026, 5, 1);

      expect(await lifecycle.markRecalled('forgotten', now: now), isFalse);
      var restored = (await service.loadEventMemories()).single;
      expect(restored.status, EventMemoryStatus.forgotten);
      expect(restored.lastRecalledAt, isNull);

      expect(await lifecycle.restore('forgotten', now: now), isTrue);
      restored = (await service.loadEventMemories()).single;
      expect(restored.status, EventMemoryStatus.active);
      expect(restored.lastRecalledAt, now);
      expect(restored.recallCount, 0);
    },
  );

  test('pendingForget recall returns to active', () async {
    final service = storage('role-a');
    await service.saveEventMemories([
      memory(
        'pending',
        DateTime.utc(2026, 1, 1),
        status: EventMemoryStatus.pendingForget,
      ),
    ]);
    final lifecycle = EventMemoryLifecycleService(
      characterId: 'role-a',
      storage: service,
    );
    expect(
      await lifecycle.markRecalled('pending', now: DateTime.utc(2026, 3, 15)),
      isTrue,
    );
    expect(
      (await service.loadEventMemories()).single.status,
      EventMemoryStatus.active,
    );
  });

  test(
    'pin is permanently active and unpin recomputes status at now',
    () async {
      final service = storage('role-a');
      final created = DateTime.utc(2026, 1, 1);
      await service.saveEventMemories([
        memory('pin', created, status: EventMemoryStatus.forgotten),
      ]);
      final lifecycle = EventMemoryLifecycleService(
        characterId: 'role-a',
        storage: service,
      );
      final now = DateTime.utc(2026, 5, 1);

      expect(
        await lifecycle.setPinned('pin', isPinned: true, now: now),
        isTrue,
      );
      var restored = (await service.loadEventMemories()).single;
      expect(restored.isPinned, isTrue);
      expect(restored.status, EventMemoryStatus.active);
      expect(
        await lifecycle.setPinned('pin', isPinned: false, now: now),
        isTrue,
      );
      restored = (await service.loadEventMemories()).single;
      expect(restored.isPinned, isFalse);
      expect(restored.status, EventMemoryStatus.forgotten);
    },
  );

  test('pin restores fading and pendingForget to active', () async {
    final service = storage('role-a');
    final created = DateTime.utc(2026, 1, 1);
    await service.saveEventMemories([
      memory('fading', created, status: EventMemoryStatus.fading),
      memory('pending', created, status: EventMemoryStatus.pendingForget),
    ]);
    final lifecycle = EventMemoryLifecycleService(
      characterId: 'role-a',
      storage: service,
    );
    final now = DateTime.utc(2026, 3, 15);
    expect(
      await lifecycle.setPinned('fading', isPinned: true, now: now),
      isTrue,
    );
    expect(
      await lifecycle.setPinned('pending', isPinned: true, now: now),
      isTrue,
    );
    final restored = await service.loadEventMemories();
    expect(restored.every((item) => item.isPinned), isTrue);
    expect(
      restored.every((item) => item.status == EventMemoryStatus.active),
      isTrue,
    );
  });

  test(
    'lifecycle and engine mutations for one character do not lose either update',
    () async {
      final service = storage('role-a');
      await service.saveEventMemories([
        memory('existing', DateTime.utc(2026, 1, 1)),
      ]);
      final lifecycle = EventMemoryLifecycleService(
        characterId: 'role-a',
        storage: service,
      );
      final engine = Memory2Engine(storage: service);
      await Future.wait([
        lifecycle.refresh(now: DateTime.utc(2026, 4, 1)),
        engine.apply(
          const MemoryExtractionResult(
            eventMemories: [
              ExtractedEventMemory(
                content: '新的共同经历',
                sourceMessageIds: ['new-source'],
              ),
            ],
          ),
          legacyViews: const [],
          now: DateTime.utc(2026, 4, 1),
        ),
      ]);

      final events = await service.loadEventMemories();
      expect(events.map((item) => item.id), containsAll(['existing']));
      expect(events.any((item) => item.content == '新的共同经历'), isTrue);
    },
  );

  test('different characters can mutate independently', () async {
    final a = storage('role-a');
    final b = storage('role-b');
    await Future.wait([
      a.upsertEventMemory(memory('a', DateTime.utc(2026, 1, 1))),
      b.upsertEventMemory(memory('b', DateTime.utc(2026, 1, 1))),
    ]);

    expect((await a.loadEventMemories()).single.characterId, 'role-a');
    expect((await b.loadEventMemories()).single.characterId, 'role-b');
  });

  test('different character mutation queues can enter concurrently', () async {
    final release = Completer<void>();
    final entered = <String>[];
    Future<void> run(String id) =>
        Memory2MutationCoordinator.runExclusive(id, () async {
          entered.add(id);
          await release.future;
        });
    final first = run('role-a');
    final second = run('role-b');
    for (var attempt = 0; attempt < 100 && entered.length < 2; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(entered, containsAll(<String>['role-a', 'role-b']));
    release.complete();
    await Future.wait([first, second]);
  });

  test(
    'lifecycle leaves User, Legacy, and Archive data unchanged and does not recall on load',
    () async {
      final service = storage('role-a');
      await service.saveEventMemories([
        memory(
          'old',
          DateTime.utc(2026, 1, 1),
          status: EventMemoryStatus.forgotten,
        ),
      ]);
      await service.saveUserMemories([
        UserMemory(id: 'user', characterId: 'role-a', key: '偏好', value: '咖啡'),
      ]);
      final legacyFile = File('${directory.path}/role-a/memories.json')
        ..parent.createSync(recursive: true);
      const legacyJson = '[{"id":"legacy","content":"旧记忆","category":"经历过的事"}]';
      await legacyFile.writeAsString(legacyJson);
      final archiveFile = File(
        '${directory.path}/role-a/character_archive.json',
      );
      const archiveJson = '{"characterId":"role-a","values":{"likes":"茶"}}';
      await archiveFile.writeAsString(archiveJson);

      expect(
        (await service.loadEventMemories()).single.status,
        EventMemoryStatus.forgotten,
      );
      expect(
        (await service.loadEventMemories()).single.status,
        EventMemoryStatus.forgotten,
      );
      await EventMemoryLifecycleService(
        characterId: 'role-a',
        storage: service,
      ).refresh(now: DateTime.utc(2026, 5, 1));

      expect((await service.loadUserMemories()).single.value, '咖啡');
      expect(await legacyFile.readAsString(), legacyJson);
      expect(await archiveFile.readAsString(), archiveJson);
      expect(
        CharacterArchive.fromJson(
          jsonDecode(await archiveFile.readAsString()),
          'role-a',
        ).value('likes'),
        '茶',
      );
    },
  );
}
