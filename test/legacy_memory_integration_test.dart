import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/legacy_memory_view.dart';
import 'package:peijianche_app/models/memory_source_type.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/services/legacy_memory_migration_service.dart';
import 'package:peijianche_app/pages/memory_page.dart';
import 'package:peijianche_app/pages/memory_review_page.dart';
import 'package:peijianche_app/services/memory2_retriever.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';
import 'package:peijianche_app/services/memory_center_controller.dart';
import 'package:peijianche_app/models/pending_memory.dart';
import 'package:peijianche_app/services/memory_review_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('legacy_integration_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => root.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> files(String id, String name) async {
    final file = File('${root.path}/characters/$id/$name');
    await file.parent.create(recursive: true);
    return file;
  }

  Memory2StorageService storage(String id) =>
      Memory2StorageService(characterId: id, fileProvider: files);

  LegacyMemoryView legacy(String id, String text) => LegacyMemoryView(
    id: 'view-$id',
    characterId: 'role-a',
    legacySourceId: id,
    kind: LegacyMemoryKind.event,
    content: text,
    category: '经历过的事',
    createdAt: DateTime.utc(2026, 8, 1),
    isPinned: false,
    legacyArchived: false,
  );

  test(
    'Memory Center copy excludes migrated legacy while retaining unmigrated legacy',
    () {
      final controller = MemoryCenterControllerForTest();
      final migrated = EventMemory(
        id: 'new-event',
        characterId: 'role-a',
        content: '共同去过海边',
        sourceType: MemorySourceType.legacy,
        legacySourceId: 'old-event',
      );
      final snapshot = controller.snapshot(
        events: [migrated],
        legacy: [legacy('old-event', '共同去过海边'), legacy('other', '旧的另一件事')],
      );
      final copied = controller.buildCopyText(snapshot);
      expect(copied, contains('共同去过海边'));
      expect(copied, contains('旧的另一件事'));
      expect(RegExp('共同去过海边').allMatches(copied).length, 1);
      expect(snapshot.migratedLegacyIds, contains('old-event'));
    },
  );

  test(
    'Retriever excludes migrated legacy but keeps eligible unmigrated fallback',
    () async {
      final event = EventMemory(
        id: 'new-event',
        characterId: 'role-a',
        content: '共同去过海边',
        sourceType: MemorySourceType.legacy,
        legacySourceId: 'old-event',
      );
      await storage('role-a').saveEventMemories([event]);
      final retriever = Memory2Retriever(
        characterId: 'role-a',
        storage: storage('role-a'),
        legacyLoader: () async => [
          legacy('old-event', '共同去过海边'),
          legacy('other', '共同去过公园'),
        ],
      );
      final result = await retriever.retrieve(
        currentMessage: '海边',
        now: DateTime.utc(2026, 8, 2),
      );
      expect(
        result.selectedEventMemories.map((e) => e.id),
        contains('new-event'),
      );
      expect(
        result.selectedLegacyMemories.map((e) => e.legacySourceId),
        isNot(contains('old-event')),
      );

      final fallback = await Memory2Retriever(
        characterId: 'role-a',
        storage: storage('role-a'),
        legacyLoader: () async => [legacy('other', '共同去过公园')],
      ).retrieve(currentMessage: '公园', now: DateTime.utc(2026, 8, 2));
      expect(
        fallback.selectedLegacyMemories.map((e) => e.legacySourceId),
        contains('other'),
      );
    },
  );

  test(
    'actual migration preserves all private and runtime sentinel bytes',
    () async {
      final protected = [
        'character_archive.json',
        'character_profile.json',
        'user_persona.json',
        'user_profile.json',
        'memory_summary.json',
        'memory_extraction_state.json',
        'memory_diagnostics.json',
      ];
      final sentinels = <String, List<int>>{};
      final globalProfile = File('${root.path}/user_profile.json');
      await globalProfile.writeAsString('global-profile-must-stay');
      for (final name in protected) {
        final file = await files('role-a', name);
        await file.writeAsString('untouched:$name');
        sentinels[name] = await file.readAsBytes();
      }
      final old = await files('role-a', 'memories.json');
      await old.writeAsString(
        '[{"id":"old","content":"旧经历","category":"经历过的事"}]',
      );
      final original = await old.readAsBytes();
      final service = LegacyMemoryMigrationService(
        characterId: 'role-a',
        fileProvider: files,
      );
      expect((await service.execute(await service.preview())).success, isTrue);
      expect(await old.readAsBytes(), original);
      expect(await globalProfile.readAsString(), 'global-profile-must-stay');
      for (final name in protected) {
        expect(
          await (await files('role-a', name)).readAsBytes(),
          sentinels[name],
        );
      }
      expect(
        (await storage('role-a').loadEventMemoriesStrict()).single.recallCount,
        0,
      );
    },
  );

  testWidgets(
    'real Memory Center preview cancel then confirm refreshes and labels legacy',
    (tester) async {
      await tester.runAsync(() async {
        final old = await files('role-a', 'memories.json');
        await old.writeAsString(
          jsonEncode([
            {
              'id': 'event-ui',
              'content': '共同参观水族馆',
              'category': '经历过的事',
              'createdAt': DateTime.now().toIso8601String(),
            },
            {'id': 'user-ui', 'content': '喜欢红茶', 'category': '关于我'},
          ]),
        );
      });
      await tester.pumpWidget(
        const MaterialApp(home: MemoryPage(characterId: 'role-a')),
      );
      await _waitForUi(tester, find.byType(SwitchListTile));
      Future<void> openPreview() async {
        await tester.tap(find.byTooltip('管理记忆'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('迁移旧版记忆'));
        await _waitForUi(tester, find.text('确认整理'));
      }

      await openPreview();
      expect(find.textContaining('关于我的记忆：1 条'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (final name in [
          'event_memories.json',
          'user_memories.json',
          LegacyMemoryMigrationService.ledgerFile,
        ]) {
          expect(await (await files('role-a', name)).exists(), isFalse);
        }
      });
      await openPreview();
      await tester.tap(find.text('确认整理'));
      await _waitForUi(tester, find.text('旧记忆已经整理到新的记忆系统中，原始数据仍为你保留。'));
      await _waitForUi(tester, find.text('喜欢红茶'));
      await tester.runAsync(() async {
        final snapshot = await MemoryCenterController(
          characterId: 'role-a',
        ).load();
        expect(snapshot.events.single.content, '共同参观水族馆');
        expect(snapshot.userMemories.single.value, '喜欢红茶');
        expect(
          snapshot.migratedLegacyIds,
          containsAll(['event-ui', 'user-ui']),
        );
        expect(
          RegExp('共同参观水族馆')
              .allMatches(
                MemoryCenterController(
                  characterId: 'role-a',
                ).buildCopyText(snapshot),
              )
              .length,
          1,
        );
      });
      await _waitForUi(tester, find.text('喜欢红茶'));
      await tester.tap(find.byTooltip('管理记忆'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('旧版记忆'));
      await tester.pumpAndSettle();
      expect(find.text('已迁移'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('legacy review page opens without rewriting candidates', (
    tester,
  ) async {
    late List<int> before;
    await tester.runAsync(() async {
      await MemoryReviewService(characterId: 'role-a').saveItems([
        PendingMemory(
          id: 'pending-ui',
          content: '旧候选可见',
          reason: '旧理由',
          category: '关于我',
        ),
      ]);
      before = await (await files(
        'role-a',
        'pending_memories.json',
      )).readAsBytes();
    });
    await tester.pumpWidget(
      const MaterialApp(home: MemoryReviewPage(characterId: 'role-a')),
    );
    await _waitForUi(tester, find.text('旧候选可见'));
    expect(find.text('旧版待审核兼容'), findsOneWidget);
    await tester.runAsync(() async {
      expect(
        await (await files('role-a', 'pending_memories.json')).readAsBytes(),
        before,
      );
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('old pending approve writes Memory2 only and removes pending', () async {
    final review = MemoryReviewService(characterId: 'role-a');
    final candidate = PendingMemory(
      id: 'pending-event',
      content: '旧版确认经历',
      reason: '测试',
      category: '经历过的事',
      createdAt: DateTime.utc(2026, 8, 1),
    );
    await review.saveItems([candidate]);
    final legacy = await files('role-a', 'memories.json');
    const legacyBytes = '[{"content":"原始旧数据","category":"其他"}]';
    await legacy.writeAsString(legacyBytes, flush: true);
    await review.approve(candidate);
    expect(await legacy.readAsString(), legacyBytes);
    expect(await review.loadItems(), isEmpty);
    final migrated = await storage('role-a').loadEventMemoriesStrict();
    expect(migrated.single.content, '旧版确认经历');
    expect(migrated.single.sourceType, MemorySourceType.legacy);
    expect(migrated.single.recallCount, 0);
  });

  test(
    'pending approve failure leaves candidate and legacy untouched',
    () async {
      final review = MemoryReviewService(characterId: 'role-a');
      final candidate = PendingMemory(
        id: 'pending-fail',
        content: '失败时保留',
        reason: '测试',
        category: '经历过的事',
      );
      await review.saveItems([candidate]);
      final legacy = await files('role-a', 'memories.json');
      const legacyBytes = '[{"content":"旧记录","category":"经历过的事"}]';
      await legacy.writeAsString(legacyBytes, flush: true);
      final memory2 = await files(
        'role-a',
        Memory2StorageService.eventFileName,
      );
      await memory2.writeAsString(
        '{"schemaVersion":999,"items":[]}',
        flush: true,
      );
      await expectLater(
        review.approve(candidate),
        throwsA(isA<FormatException>()),
      );
      expect((await review.loadItems()).single.id, 'pending-fail');
      expect(await legacy.readAsString(), legacyBytes);
    },
  );
}

Future<void> _waitForUi(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('UI did not finish local file loading: $finder');
}

// Small adapter keeps this integration test independent from widget internals.
class MemoryCenterControllerForTest {
  MemoryCenterSnapshot snapshot({
    required List<EventMemory> events,
    required List<LegacyMemoryView> legacy,
  }) => MemoryCenterSnapshot(
    events: events,
    userMemories: const [],
    summary: MemorySummary(characterId: 'role-a'),
    characterUserProfile: const CharacterUserProfile(characterId: 'role-a'),
    settings: CharacterSettings.genericDefaults(),
    legacy: legacy,
    migratedLegacyIds: {'old-event'},
  );

  String buildCopyText(MemoryCenterSnapshot snapshot) =>
      MemoryCenterController(characterId: 'role-a').buildCopyText(snapshot);
}
