import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/memory_extraction_result.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/services/auto_memory_extraction_service.dart';
import 'package:peijianche_app/services/event_memory_lifecycle_service.dart';
import 'package:peijianche_app/services/explicit_remember_intent.dart';
import 'package:peijianche_app/services/memory2_chat_context_builder.dart';
import 'package:peijianche_app/services/memory2_engine.dart';
import 'package:peijianche_app/services/memory2_extractor.dart';
import 'package:peijianche_app/services/memory2_retriever.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';
import 'package:peijianche_app/services/memory_center_controller.dart';
import 'package:peijianche_app/services/memory_extraction_state_service.dart';

class _Gateway implements Memory2ExtractionGateway {
  MemoryExtractionResult result = const MemoryExtractionResult();
  Object? error;
  Completer<void>? wait;
  int calls = 0;
  Memory2ExtractionRequest? request;
  @override
  Future<MemoryExtractionResult> extract(Memory2ExtractionRequest value) async {
    calls++;
    request = value;
    if (wait != null) await wait!.future;
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  late Directory temp;
  late Memory2StorageService storage;
  late MemoryExtractionStateService state;
  late _Gateway gateway;
  late List<ChatMessage> messages;
  final now = DateTime.utc(2026, 9, 4);
  ChatMessage user(String text, {String id = 'u'}) =>
      ChatMessage(id: id, role: 'user', content: text, createdAt: now);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('memory201_');
    storage = Memory2StorageService(
      characterId: 'c',
      fileProvider: (_, name) async => File('${temp.path}/$name'),
    );
    state = MemoryExtractionStateService(
      characterId: 'c',
      fileProvider: (_) async => File('${temp.path}/state.json'),
    );
    gateway = _Gateway();
    messages = [
      user('你一定要记住，我们一起去了海边。'),
      ChatMessage(id: 'a', role: 'assistant', content: '好的', createdAt: now),
    ];
  });
  tearDown(() async => temp.delete(recursive: true));
  AutoMemoryExtractionService service({bool enabled = true}) =>
      AutoMemoryExtractionService(
        characterId: 'c',
        gateway: gateway,
        storage: storage,
        stateService: state,
        messagesLoader: () async => messages,
        legacyLoader: () async => [],
        settingsLoader: () async => CharacterSettings.genericDefaults()
            .copyWith(autoMemoryEnabled: enabled),
        userNameLoader: () async => '用户',
        logger: (_) {},
      );
  Memory2Retriever retriever() => Memory2Retriever(
    characterId: 'c',
    storage: storage,
    lifecycle: EventMemoryLifecycleService(characterId: 'c', storage: storage),
    legacyLoader: () async => [],
    logger: (_) {},
  );
  void eventResult() {
    gateway.result = const MemoryExtractionResult(
      eventMemories: [
        ExtractedEventMemory(content: '一起去了海边', sourceMessageIds: ['u']),
      ],
    );
  }

  UserMemory old({bool confirmed = false, bool pinned = false}) => UserMemory(
    id: 'old',
    characterId: 'c',
    key: '喜欢的饮品',
    value: '咖啡',
    sourceMessageIds: ['original'],
    createdAt: now.subtract(const Duration(days: 100)),
    userConfirmed: confirmed,
    isPinned: pinned,
  );
  Future<void> change({
    String evidence = '以前喜欢咖啡，现在更喜欢茶',
    bool confirmed = false,
    bool pinned = false,
  }) async {
    await storage.saveUserMemories([old(confirmed: confirmed, pinned: pinned)]);
    await Memory2Engine(storage: storage).apply(
      MemoryExtractionResult(
        userMemories: [
          ExtractedUserMemory(
            key: '喜欢的饮品',
            value: '茶',
            sourceMessageIds: const ['u'],
            supersedesId: 'old',
            changeEvidence: evidence,
          ),
        ],
      ),
      legacyViews: [],
      now: now,
      sourceMessages: [user(evidence)],
    );
  }

  for (final text in [
    '这个你一定要记住。',
    '这件事对我很重要，别忘了。',
    '以后记得我不吃香菜。',
    '你要记住，我们的纪念日是六月一日。',
  ]) {
    test(
      'direct save intent: $text',
      () => expect(ExplicitRememberIntent.detect(user(text)), isNotNull),
    );
  }
  for (final text in [
    '你还记得吗？',
    '我记得以前去过那里',
    '不用记这个',
    '你不用记这个',
    '别忘了提醒我明天买水。',
    '他说“你一定要记住”。',
    '“你要记住这个”',
    '开玩笑的，你一定要记住。',
  ]) {
    test(
      'not a save command: $text',
      () => expect(ExplicitRememberIntent.detect(user(text)), isNull),
    );
  }
  test(
    'below threshold explicit event pins without advancing ordinary cursor',
    () async {
      eventResult();
      expect(
        await service().maybeExtract(now: now),
        AutoMemoryExtractionOutcome.success,
      );
      final event = (await storage.loadEventMemories()).single;
      expect(event.isPinned, isTrue);
      expect(event.status, EventMemoryStatus.active);
      expect((await state.load()).lastProcessedMessageId, isNull);
      expect((await state.load()).explicitAttempts['u'], 'success');
      expect(
        await service().maybeExtract(now: now),
        AutoMemoryExtractionOutcome.insufficientMessages,
      );
      expect(gateway.calls, 1);
      expect(
        EventMemoryLifecycleService(
          characterId: 'c',
        ).evaluateStatus(event, now.add(const Duration(days: 1000))),
        EventMemoryStatus.active,
      );
    },
  );
  test(
    'explicit command is authorized even with automatic collection disabled',
    () async {
      eventResult();
      expect(
        await service(enabled: false).maybeExtract(),
        AutoMemoryExtractionOutcome.success,
      );
    },
  );
  test('explicit user confirms and is not also copied as event', () async {
    messages[0] = user('以后记得我不吃香菜');
    gateway.result = const MemoryExtractionResult(
      userMemories: [
        ExtractedUserMemory(key: '忌口', value: '不吃香菜', sourceMessageIds: ['u']),
      ],
      eventMemories: [
        ExtractedEventMemory(content: '不吃香菜', sourceMessageIds: ['u']),
      ],
    );
    await service().maybeExtract();
    final item = (await storage.loadUserMemories()).single;
    expect(item.userConfirmed, isTrue);
    expect(item.isPinned, isFalse);
    expect(await storage.loadEventMemories(), isEmpty);
  });
  test(
    'deictic request gets only nearby user target and not whole batch',
    () async {
      messages = [
        user('无关旧话题', id: 'old'),
        user('我们今天一起去了海边', id: 'target'),
        ChatMessage(role: 'assistant', content: '幻想内容'),
        user('你一定要记住'),
      ];
      await service().maybeExtract();
      expect(gateway.request!.messages.map((m) => m.id), ['target', 'u']);
    },
  );
  for (final error in [
    StateError('offline'),
    const MemoryExtractionParseException(
      'invalid',
      shape: MemoryExtractionRawResponseShape.invalid,
    ),
  ]) {
    test(
      'explicit failure isolated and never automatically loops: ${error.runtimeType}',
      () async {
        gateway.error = error;
        expect(
          await service().maybeExtract(now: now),
          AutoMemoryExtractionOutcome.failed,
        );
        for (var i = 0; i < 4; i++) {
          await service().maybeExtract(now: now.add(Duration(days: i)));
        }
        expect(gateway.calls, 1);
        expect((await state.load()).explicitAttempts['u'], 'failed');
        expect((await state.load()).lastProcessedMessageId, isNull);
        expect(await storage.loadEventMemories(), isEmpty);
      },
    );
  }
  test(
    'empty is recoverable through Memory Center retry with exact source',
    () async {
      expect(
        await service().maybeExtract(),
        AutoMemoryExtractionOutcome.explicitEmpty,
      );
      final controller = MemoryCenterController(
        characterId: 'c',
        storage: storage,
        extractionState: state,
        messagesLoader: () async => messages,
        explicitServiceFactory: service,
      );
      expect((await controller.loadExplicitFailures()).single.messageId, 'u');
      eventResult();
      expect(
        await controller.retryExplicit('u'),
        AutoMemoryExtractionOutcome.success,
      );
      expect(gateway.calls, 2);
      expect(await controller.loadExplicitFailures(), isEmpty);
    },
  );
  test('explicit and ordinary extraction share role lock', () async {
    gateway.wait = Completer<void>();
    final running = service().maybeExtract();
    while (gateway.calls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(
      await service().maybeExtract(),
      AutoMemoryExtractionOutcome.alreadyRunning,
    );
    gateway.wait!.complete();
    await running;
    expect(gateway.calls, 1);
  });
  test(
    'reply-bound explicit request waits for busy role without being dropped',
    () async {
      gateway.wait = Completer<void>();
      final first = service().maybeExtract();
      while (gateway.calls == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      messages = [...messages, user('你要记住我们的纪念日是六月一日', id: 'second')];
      final second = service().maybeExtract(explicitMessageId: 'second');
      gateway.wait!.complete();
      await first;
      await second;
      expect(gateway.calls, 2);
      expect(
        (await state.load()).explicitAttempts.keys,
        containsAll(['u', 'second']),
      );
      expect(gateway.request!.messages.single.id, 'second');
    },
  );
  test(
    'saved reply dispatch returns before failed extraction and unsaved reply never dispatches',
    () async {
      gateway.wait = Completer<void>();
      gateway.error = StateError('offline');
      AutoMemoryExtractionService.afterReplySaved(
        characterId: 'c',
        replyPersisted: false,
        userMessageId: 'u',
        factory: service,
      );
      await Future<void>.delayed(Duration.zero);
      expect(gateway.calls, 0);
      AutoMemoryExtractionService.afterReplySaved(
        characterId: 'c',
        replyPersisted: true,
        userMessageId: 'u',
        factory: service,
      );
      while (gateway.calls == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(gateway.wait!.isCompleted, isFalse);
      gateway.wait!.complete();
      while (AutoMemoryExtractionService.isRunning('c')) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect((await state.load()).explicitAttempts['u'], 'failed');
    },
  );
  test(
    'quoted or hypothetical correction cannot replace current fact',
    () async {
      for (final text in [
        '他说“以前喜欢咖啡，现在更喜欢茶”',
        '如果以前喜欢咖啡，现在更喜欢茶，该怎么表达？',
        '以前喜欢咖啡，现在更喜欢茶，开玩笑的',
      ]) {
        await storage.saveUserMemories([old()]);
        await Memory2Engine(storage: storage).apply(
          const MemoryExtractionResult(
            userMemories: [
              ExtractedUserMemory(
                key: '喜欢的饮品',
                value: '茶',
                sourceMessageIds: ['u'],
                supersedesId: 'old',
                changeEvidence: '以前喜欢咖啡，现在更喜欢茶',
              ),
            ],
          ),
          legacyViews: [],
          sourceMessages: [user(text)],
        );
        expect((await storage.loadUserMemories()).single.value, '咖啡');
      }
    },
  );
  test(
    'history has separate two-item cap while current stays active',
    () async {
      await storage.saveUserMemories([
        for (var i = 0; i < 4; i++)
          UserMemory(
            id: 'h$i',
            characterId: 'c',
            key: '喜欢的饮品',
            value: '咖啡$i',
            status: UserMemoryStatus.superseded,
            supersededById: 'current',
          ),
        UserMemory(id: 'current', characterId: 'c', key: '喜欢的饮品', value: '茶'),
      ]);
      final result = await retriever().retrieve(
        currentMessage: '以前我更喜欢什么饮品',
        now: now,
      );
      expect(result.selectedHistoricalUserMemories.length, 2);
      expect(result.selectedUserMemories.single.value, '茶');
    },
  );
  test('explicit duplicate resurrects and pins existing event', () async {
    await storage.saveEventMemories([
      EventMemory(
        id: 'old',
        characterId: 'c',
        content: '一起去了海边',
        status: EventMemoryStatus.forgotten,
      ),
    ]);
    eventResult();
    await service().maybeExtract();
    final item = (await storage.loadEventMemories()).single;
    expect(item.id, 'old');
    expect(item.isPinned, isTrue);
    expect(item.status, EventMemoryStatus.active);
  });
  test(
    'supersede preserves old identity provenance and links new version',
    () async {
      await change();
      final items = await storage.loadUserMemories();
      final a = items.first;
      final b = items.last;
      expect(items.length, 2);
      expect(a.value, '咖啡');
      expect(a.id, 'old');
      expect(a.createdAt, old().createdAt);
      expect(a.sourceType, old().sourceType);
      expect(a.sourceMessageIds, ['original']);
      expect(a.status, UserMemoryStatus.superseded);
      expect(a.supersededById, b.id);
      expect(b.mergedFromIds, ['old']);
      expect(b.sourceMessageIds, ['u']);
      expect(b.status, UserMemoryStatus.active);
    },
  );
  for (final protection in ['confirmed', 'pinned']) {
    test(
      'direct evidenced correction retains $protection protection on both versions',
      () async {
        await change(
          evidence: '我之前说错了，其实我不喝咖啡',
          confirmed: protection == 'confirmed',
          pinned: protection == 'pinned',
        );
        final items = await storage.loadUserMemories();
        expect(items.length, 2);
        expect(
          items.every(
            (m) => protection == 'confirmed' ? m.userConfirmed : m.isPinned,
          ),
          isTrue,
        );
      },
    );
  }
  test(
    'different value without evidence never overwrites protected or ordinary facts',
    () async {
      for (final protected in [false, true]) {
        await storage.saveUserMemories([old(confirmed: protected)]);
        await Memory2Engine(storage: storage).apply(
          const MemoryExtractionResult(
            userMemories: [
              ExtractedUserMemory(
                key: '喜欢的饮品',
                value: '茶',
                sourceMessageIds: ['u'],
              ),
            ],
          ),
          legacyViews: [],
        );
        expect((await storage.loadUserMemories()).single.value, '咖啡');
      }
    },
  );
  test(
    'coexisting preferences never supersede even if model claims they do',
    () async {
      await change(evidence: '以前喜欢咖啡，现在咖啡和茶都喜欢');
      expect(
        (await storage.loadUserMemories()).single.status,
        UserMemoryStatus.active,
      );
    },
  );
  test('fabricated change evidence cannot retire a fact', () async {
    await storage.saveUserMemories([old()]);
    await Memory2Engine(storage: storage).apply(
      const MemoryExtractionResult(
        userMemories: [
          ExtractedUserMemory(
            key: '喜欢的饮品',
            value: '茶',
            sourceMessageIds: ['u'],
            supersedesId: 'old',
            changeEvidence: '现在只喝茶',
          ),
        ],
      ),
      legacyViews: [],
      sourceMessages: [user('我喜欢咖啡也喜欢茶')],
    );
    expect((await storage.loadUserMemories()).single.value, '咖啡');
  });
  test(
    'ordinary recall excludes history; explicit history has current companion and cap',
    () async {
      await change();
      var result = await retriever().retrieve(
        currentMessage: '我喜欢的饮品是什么',
        now: now,
      );
      expect(result.selectedHistoricalUserMemories, isEmpty);
      expect(result.selectedUserMemories.single.value, '茶');
      result = await retriever().retrieve(
        currentMessage: '我以前是不是喜欢咖啡',
        now: now,
      );
      expect(result.selectedHistoricalUserMemories.single.value, '咖啡');
      expect(result.contextText, contains('当前：喜欢的饮品：茶'));
      expect(result.contextText, contains('仅回答过去，当前事实优先'));
      expect(
        result.contextText.length,
        lessThanOrEqualTo(Memory2Retriever.totalContextCharacters),
      );
    },
  );
  test(
    'historical intent does not admit unrelated or archived facts',
    () async {
      await change();
      final items = await storage.loadUserMemories();
      await storage.saveUserMemories([
        ...items,
        UserMemory(
          id: 'archived',
          characterId: 'c',
          key: '喜欢',
          value: '游泳',
          status: UserMemoryStatus.archived,
        ),
      ]);
      final result = await retriever().retrieve(
        currentMessage: '之前我的习惯是什么',
        now: now,
      );
      expect(result.selectedHistoricalUserMemories, isEmpty);
    },
  );
  test('stale Summary cannot outrank current active fact in prompt', () async {
    await change();
    await storage.saveMemorySummary(
      const MemorySummary(characterId: 'c', generatedText: '喜欢的饮品是咖啡'),
    );
    final result = await retriever().retrieve(
      currentMessage: '现在喜欢的饮品是什么',
      now: now,
    );
    final prompt = Memory2ChatContextBuilder.build(
      retrieval: result,
      characterUserProfile: const CharacterUserProfile(characterId: 'c'),
    );
    expect(result.selectedUserMemories.single.value, '茶');
    expect(prompt, contains('当前 active 用户事实优先于长期汇总（Summary）中的旧事实'));
    expect(prompt, contains('喜欢的饮品：茶'));
    expect((await storage.loadMemorySummary()).generatedText, '喜欢的饮品是咖啡');
  });
  test('ordinary lifecycle boundaries remain 30 60 90', () {
    final lifecycle = EventMemoryLifecycleService(characterId: 'c');
    final e = EventMemory(
      id: 'e',
      characterId: 'c',
      content: '普通事件',
      createdAt: now,
    );
    for (final entry in {
      29: EventMemoryStatus.active,
      30: EventMemoryStatus.fading,
      60: EventMemoryStatus.pendingForget,
      90: EventMemoryStatus.forgotten,
    }.entries) {
      expect(
        lifecycle.evaluateStatus(e, now.add(Duration(days: entry.key))),
        entry.value,
      );
    }
  });
  test('explicit writes create no Pending or Legacy files', () async {
    eventResult();
    await service().maybeExtract();
    final names = await temp
        .list()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(names.toSet(), {
      'state.json',
      'event_memories.json',
      'user_memories.json',
    });
  });
}
