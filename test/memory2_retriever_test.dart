import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/legacy_memory_view.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/services/event_memory_lifecycle_service.dart';
import 'package:peijianche_app/services/memory2_chat_context_builder.dart';
import 'package:peijianche_app/services/memory2_retriever.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';
import 'package:peijianche_app/services/memory_diagnostics_service.dart';

void main() {
  late Directory directory;
  final now = DateTime.utc(2026, 8, 1);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('memory2_retriever_');
  });

  tearDown(() async {
    MemoryDiagnosticsService.debugEnabledOverride = null;
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Memory2StorageService storage(String characterId) => Memory2StorageService(
    characterId: characterId,
    fileProvider: (id, fileName) async =>
        File('${directory.path}/$id/$fileName'),
  );

  EventMemory event(
    String id,
    String content, {
    DateTime? createdAt,
    EventMemoryStatus status = EventMemoryStatus.active,
    bool pinned = false,
  }) {
    return EventMemory(
      id: id,
      characterId: 'role-a',
      content: content,
      createdAt: createdAt ?? now.subtract(const Duration(days: 2)),
      updatedAt: now,
      status: status,
      isPinned: pinned,
      sourceMessageIds: [id],
    );
  }

  UserMemory user(String id, String key, String value) => UserMemory(
    id: id,
    characterId: 'role-a',
    key: key,
    value: value,
    updatedAt: now,
    createdAt: now.subtract(const Duration(days: 1)),
  );

  LegacyMemoryView legacy(
    String id,
    LegacyMemoryKind kind,
    String content, {
    bool archived = false,
  }) => LegacyMemoryView(
    id: 'view-$id',
    characterId: 'role-a',
    legacySourceId: id,
    kind: kind,
    content: content,
    category: kind == LegacyMemoryKind.event ? '经历过的事' : '关于我',
    createdAt: now,
    isPinned: false,
    legacyArchived: archived,
  );

  Memory2Retriever retriever(
    Memory2StorageService service, {
    List<LegacyMemoryView> legacyViews = const [],
  }) => Memory2Retriever(
    characterId: 'role-a',
    storage: service,
    lifecycle: EventMemoryLifecycleService(
      characterId: 'role-a',
      storage: service,
    ),
    legacyLoader: () async => legacyViews,
  );

  test(
    'retrieves relevant active/fading/pending and pinned events, excludes forgotten',
    () async {
      final service = storage('role-a');
      await service.saveEventMemories([
        event('active', '我们在海边散步'),
        event(
          'fading',
          '我们在海边看日落',
          createdAt: now.subtract(const Duration(days: 40)),
        ),
        event(
          'pending',
          '我们在海边捡贝壳',
          createdAt: now.subtract(const Duration(days: 70)),
        ),
        event(
          'forgotten',
          '我们在海边露营',
          createdAt: now.subtract(const Duration(days: 100)),
        ),
        event(
          'pinned',
          '我们在海边看星星',
          createdAt: now.subtract(const Duration(days: 100)),
          pinned: true,
        ),
        event('unrelated', '一起整理书架'),
      ]);

      final result = await retriever(
        service,
      ).retrieve(currentMessage: '海边', now: now);
      final ids = result.selectedEventMemories.map((item) => item.id).toSet();
      expect(ids, hasLength(Memory2Retriever.maximumEventMemories));
      expect(ids, contains('pinned'));
      expect(result.diagnostics.eventCandidates, 4);
      expect(ids, isNot(contains('forgotten')));
      expect(ids, isNot(contains('unrelated')));
    },
  );

  test(
    'status thresholds keep fading searchable and pending requires high relevance',
    () async {
      final service = storage('role-a');
      await service.saveEventMemories([
        event(
          'fading',
          '我们一起挑选蓝色裙子',
          createdAt: now.subtract(const Duration(days: 40)),
        ),
        event(
          'pending-high',
          '用户给角色看过蓝色裙子',
          createdAt: now.subtract(const Duration(days: 70)),
        ),
        event(
          'pending-low',
          '我们曾讨论周末去山顶',
          createdAt: now.subtract(const Duration(days: 70)),
        ),
        event('pinned-unrelated', '一起整理旧书架', pinned: true),
      ]);
      final result = await retriever(
        service,
      ).retrieve(currentMessage: '蓝色裙子', now: now);
      final ids = result.selectedEventMemories.map((item) => item.id).toSet();
      expect(ids, containsAll(<String>['fading', 'pending-high']));
      expect(ids, isNot(contains('pending-low')));
      expect(ids, isNot(contains('pinned-unrelated')));
    },
  );

  test(
    'relevant old memory outranks newer unrelated memory and recent chat assists query',
    () async {
      final service = storage('role-a');
      await service.saveEventMemories([
        event(
          'old-relevant',
          '我们曾在山顶看日出',
          createdAt: now.subtract(const Duration(days: 20)),
        ),
        event(
          'new-unrelated',
          '一起整理书架',
          createdAt: now.subtract(const Duration(days: 1)),
        ),
      ]);
      final result = await retriever(
        service,
      ).retrieve(currentMessage: '你觉得怎么样', recentMessages: const [], now: now);
      expect(result.selectedEventMemories, isEmpty);

      final assisted = await retriever(service).retrieve(
        currentMessage: '你觉得怎么样',
        recentMessages: [
          ChatMessage(id: 'recent', role: 'user', content: '山顶日出'),
        ],
        now: now,
      );
      expect(assisted.selectedEventMemories.single.id, 'old-relevant');
    },
  );

  test(
    'explicit current topic suppresses unrelated recent context expansion',
    () async {
      final service = storage('role-a');
      await service.saveEventMemories([event('hydrangea', '我们把蓝色绣球放在电脑桌旁')]);
      final result = await retriever(service).retrieve(
        currentMessage: '我其实更喜欢剧情和 PVE，不喜欢 PVP',
        recentMessages: [
          ChatMessage(id: 'recent', role: 'user', content: '蓝色绣球放在电脑桌旁'),
        ],
        now: now,
      );
      expect(result.selectedEventMemories, isEmpty);
    },
  );

  test('common English words do not create false relevance', () async {
    final service = storage('role-a');
    await service.saveEventMemories([
      event(
        'hydrangea-en',
        'The user bought a blue hydrangea and placed it beside the computer',
      ),
    ]);
    final result = await retriever(service).retrieve(
      currentMessage: 'I prefer story and PVE games over PVP',
      recentMessages: [
        ChatMessage(id: 'recent', role: 'user', content: 'blue hydrangea'),
      ],
      now: now,
    );
    expect(result.selectedEventMemories, isEmpty);
  });

  test('ambiguous reference uses recent context as a decayed aid', () async {
    final service = storage('role-a');
    await service.saveEventMemories([event('hydrangea', '我们把蓝色绣球放在电脑桌旁')]);
    MemoryDiagnosticsService.debugEnabledOverride = true;
    final result = await retriever(service).retrieve(
      currentMessage: '那个最后放哪了？',
      recentMessages: [ChatMessage(id: 'older', role: 'user', content: '蓝色绣球')],
      now: now,
    );
    expect(result.selectedEventMemories.single.id, 'hydrangea');
    final item = MemoryDiagnosticsService.retrieverFor(
      'role-a',
    )!.eventItems.single;
    expect(item.currentQueryContribution, 0);
    expect(item.contextExpansionContribution, greaterThan(0));
    expect(item.contextExpansionContribution, lessThanOrEqualTo(0.30));
  });

  test('context expansion contribution decays with message distance', () async {
    final service = storage('role-a');
    await service.saveEventMemories([event('hydrangea', '蓝色绣球放在电脑桌旁')]);
    MemoryDiagnosticsService.debugEnabledOverride = true;
    final recent = <ChatMessage>[
      ChatMessage(id: 'oldest', role: 'user', content: '蓝色绣球'),
      ChatMessage(id: 'middle', role: 'user', content: '今天继续聊天'),
      ChatMessage(id: 'newest', role: 'user', content: '刚刚的无关话题'),
    ];
    await retriever(
      service,
    ).retrieve(currentMessage: '那个呢？', recentMessages: recent, now: now);
    final item = MemoryDiagnosticsService.retrieverFor(
      'role-a',
    )!.eventItems.single;
    expect(item.contextExpansionContribution, closeTo(0.08, 0.0001));
  });

  test('recall intent does not bypass unrelated event relevance', () async {
    final service = storage('role-a');
    await service.saveEventMemories([event('unrelated', '我们一起整理书架')]);
    final result = await retriever(
      service,
    ).retrieve(currentMessage: '你还记得蓝色绣球吗？', now: now);
    expect(result.diagnostics.recallIntent, isTrue);
    expect(result.selectedEventMemories, isEmpty);
  });

  test(
    'retrieval caps events at three and users at four by relevance',
    () async {
      final service = storage('role-a');
      await service.saveEventMemories([
        event('e1', '海边经历一'),
        event('e2', '海边经历二'),
        event('e3', '海边经历三'),
        event('e4', '海边经历四'),
        event('e5', '海边经历五'),
      ]);
      await service.saveUserMemories([
        user('u1', '喜欢海边一', '喜欢'),
        user('u2', '喜欢海边二', '喜欢'),
        user('u3', '喜欢海边三', '喜欢'),
        user('u4', '喜欢海边四', '喜欢'),
        user('u5', '喜欢海边五', '喜欢'),
      ]);

      final result = await retriever(
        service,
      ).retrieve(currentMessage: '海边', now: now);
      expect(result.selectedEventMemories, hasLength(3));
      expect(result.selectedUserMemories, hasLength(4));
      expect(
        result.selectedEventMemories.map((item) => item.content),
        everyElement(contains('海边')),
      );
      expect(
        result.selectedUserMemories.map((item) => item.displayText),
        everyElement(contains('海边')),
      );
    },
  );

  test(
    'summary uses edited text, empty summary is omitted, and context builder filters empty profile',
    () async {
      final service = storage('role-a');
      await service.saveMemorySummary(
        MemorySummary(
          characterId: 'role-a',
          generatedText: 'generated summary',
          userEditedText: 'edited summary',
        ),
      );
      final result = await retriever(
        service,
      ).retrieve(currentMessage: 'summary', now: now);
      expect(result.memorySummary.effectiveText, 'edited summary');
      expect(result.contextText, contains('edited summary'));
      expect(result.contextText, isNot(contains('generated summary')));
      expect(
        Memory2ChatContextBuilder.build(
          retrieval: result,
          characterUserProfile: const CharacterUserProfile(
            characterId: 'role-a',
          ),
        ),
        contains('edited summary'),
      );

      await service.saveMemorySummary(
        const MemorySummary(characterId: 'role-a'),
      );
      final empty = await retriever(
        service,
      ).retrieve(currentMessage: 'nothing', now: now);
      expect(empty.memorySummary.effectiveText, isEmpty);
      expect(empty.contextText, isNot(contains('长期记忆汇总')));
    },
  );

  test(
    'legacy event/user are fallback only; archived and unclassified are excluded; new duplicate wins',
    () async {
      final service = storage('role-a');
      await service.saveEventMemories([event('new', '一起在海边散步')]);
      final views = [
        legacy('old-event', LegacyMemoryKind.event, '一起在海边散步'),
        legacy('old-user', LegacyMemoryKind.user, '喜欢咖啡'),
        legacy('archived', LegacyMemoryKind.event, '海边旧记录', archived: true),
        legacy('unknown', LegacyMemoryKind.legacyUnclassified, '未知旧分类'),
      ];
      final result = await retriever(
        service,
        legacyViews: views,
      ).retrieve(currentMessage: '咖啡', now: now);
      expect(result.selectedLegacyMemories.map((item) => item.legacySourceId), [
        'old-user',
      ]);
      expect(result.contextText, isNot(contains('未知旧分类')));
      expect(result.contextText, isNot(contains('海边旧记录')));
      expect(result.contextText, isNot(contains('一起在海边散步')));

      await service.deleteEventMemory('new');
      final eventFallback = await retriever(
        service,
        legacyViews: views,
      ).retrieve(currentMessage: '海边散步', now: now);
      expect(
        eventFallback.selectedLegacyMemories.map((item) => item.legacySourceId),
        contains('old-event'),
      );
    },
  );

  test('budget and per-item truncation bound context', () async {
    final service = storage('role-a');
    await service.saveMemorySummary(
      MemorySummary(characterId: 'role-a', generatedText: '摘要' * 700),
    );
    await service.saveEventMemories([event('long', '海边' * 300)]);
    final result = await retriever(
      service,
    ).retrieve(currentMessage: '海边', now: now);
    expect(
      result.contextText.length,
      lessThanOrEqualTo(Memory2Retriever.totalContextCharacters),
    );
    expect(result.selectedEventMemories.single.content.length, 600);
    expect(result.contextText, contains('…'));
  });

  test(
    'recall intent changes diagnostics and only injected events are recalled',
    () async {
      final service = storage('role-a');
      await service.saveEventMemories([event('event', '之前我们在海边散步')]);
      final retrieverInstance = retriever(service);
      final scan = await retrieverInstance.retrieve(
        currentMessage: '海边',
        now: now,
      );
      expect(scan.diagnostics.recallIntent, isFalse);
      expect((await service.loadEventMemories()).single.recallCount, 0);

      final recall = await retrieverInstance.retrieve(
        currentMessage: '你还记得海边吗？',
        now: now,
      );
      expect(recall.diagnostics.recallIntent, isTrue);
      expect((await service.loadEventMemories()).single.recallCount, 0);
      await retrieverInstance.recordInjectedEvents(
        recall.injectedEventIds,
        now: now,
      );
      expect((await service.loadEventMemories()).single.recallCount, 1);
    },
  );

  test(
    'recall intent lowers Event threshold without returning all events',
    () async {
      final service = storage('role-a');
      await service.saveEventMemories([
        event(
          'borderline',
          '用户展示过蓝色裙子',
          createdAt: now.subtract(const Duration(days: 70)),
        ),
        event('unrelated', '一起整理书架'),
      ]);
      final plain = await retriever(
        service,
      ).retrieve(currentMessage: '那件蓝色衣服', now: now);
      expect(plain.selectedEventMemories, isEmpty);
      final recalled = await retriever(
        service,
      ).retrieve(currentMessage: '还记得那件蓝色衣服吗', now: now);
      expect(recalled.selectedEventMemories.single.id, 'borderline');
      expect(
        recalled.selectedEventMemories.map((item) => item.id),
        isNot(contains('unrelated')),
      );
    },
  );

  test(
    'recordInjectedEvents swallows recall failures and retrieval refreshes lifecycle first',
    () async {
      final service = storage('role-a');
      await service.saveEventMemories([
        event('old', '海边经历', createdAt: now.subtract(const Duration(days: 90))),
      ]);
      final retrieverInstance = retriever(service);
      final result = await retrieverInstance.retrieve(
        currentMessage: '海边',
        now: now,
      );
      expect(result.selectedEventMemories, isEmpty);
      expect(result.diagnostics.lifecycleRefreshSucceeded, isTrue);
      await retrieverInstance.recordInjectedEvents([
        'missing',
        'old',
      ], now: now);
      expect(
        (await service.loadEventMemories()).single.status,
        EventMemoryStatus.forgotten,
      );
    },
  );

  test(
    'corrupt files degrade safely without changing legacy, Archive, or cursor files',
    () async {
      final service = storage('role-a');
      final roleDirectory = Directory('${directory.path}/role-a')
        ..createSync(recursive: true);
      final eventFile = File(
        '${roleDirectory.path}/${Memory2StorageService.eventFileName}',
      )..writeAsStringSync('{broken');
      final userFile = File(
        '${roleDirectory.path}/${Memory2StorageService.userFileName}',
      )..writeAsStringSync('[]');
      final summaryFile = File(
        '${roleDirectory.path}/${Memory2StorageService.summaryFileName}',
      )..writeAsStringSync(jsonEncode({'schemaVersion': 999}));
      final legacyFile = File('${roleDirectory.path}/memories.json')
        ..writeAsStringSync('[{"content":"legacy"}]');
      final archiveFile = File('${roleDirectory.path}/character_archive.json')
        ..writeAsStringSync('{"characterId":"role-a","values":{"likes":"茶"}}');
      final cursorFile =
          File('${roleDirectory.path}/memory_extraction_state.json')
            ..writeAsStringSync(
              '{"schemaVersion":2,"state":{"lastProcessedMessageId":"m1"}}',
            );

      final result = await retriever(
        service,
      ).retrieve(currentMessage: 'anything', now: now);
      expect(result.selectedEventMemories, isEmpty);
      expect(result.selectedUserMemories, isEmpty);
      expect(result.memorySummary.effectiveText, isEmpty);
      expect(await legacyFile.readAsString(), '[{"content":"legacy"}]');
      expect(
        await archiveFile.readAsString(),
        '{"characterId":"role-a","values":{"likes":"茶"}}',
      );
      expect(
        await cursorFile.readAsString(),
        '{"schemaVersion":2,"state":{"lastProcessedMessageId":"m1"}}',
      );
      expect(await eventFile.readAsString(), '{broken');
      expect(await userFile.readAsString(), '[]');
      expect(
        await summaryFile.readAsString(),
        jsonEncode({'schemaVersion': 999}),
      );
    },
  );

  test('User retrieval does not mutate Event memories', () async {
    final service = storage('role-a');
    await service.saveEventMemories([event('event', '海边经历')]);
    await service.saveUserMemories([user('user', '喜欢', '海边')]);
    final before = (await service.loadEventMemories()).single.toJson();
    await retriever(service).retrieve(currentMessage: '海边', now: now);
    expect((await service.loadEventMemories()).single.toJson(), before);
  });
}
