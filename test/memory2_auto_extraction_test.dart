import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/legacy_memory_view.dart';
import 'package:peijianche_app/models/memory_extraction_result.dart';
import 'package:peijianche_app/models/memory_extraction_state.dart';
import 'package:peijianche_app/models/memory_source_type.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/services/memory2_engine.dart';
import 'package:peijianche_app/services/memory2_extractor.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';
import 'package:peijianche_app/services/memory_extraction_state_service.dart';
import 'package:peijianche_app/services/auto_memory_extraction_service.dart';

class _FakeGateway implements Memory2ExtractionGateway {
  _FakeGateway({this.result, this.error, this.blocker});

  int calls = 0;
  Memory2ExtractionRequest? request;
  final MemoryExtractionResult? result;
  final Object? error;
  final Completer<void>? blocker;

  @override
  Future<MemoryExtractionResult> extract(Memory2ExtractionRequest value) async {
    calls++;
    request = value;
    if (error != null) throw error!;
    if (blocker != null) await blocker!.future;
    return result ??
        const MemoryExtractionResult(
          eventMemories: [
            ExtractedEventMemory(content: '本批共同经历', sourceMessageIds: ['m8']),
          ],
        );
  }
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('memory2_extract_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Memory2StorageService storage(String characterId) => Memory2StorageService(
    characterId: characterId,
    fileProvider: (id, fileName) async =>
        File('${directory.path}/$id/$fileName'),
  );

  List<ChatMessage> batch({String prefix = 'm'}) => List<ChatMessage>.generate(
    8,
    (index) => ChatMessage(
      id: '$prefix${index + 1}',
      role: index.isEven ? 'user' : 'assistant',
      content: '消息 ${index + 1}',
      createdAt: DateTime.utc(2026, 8, 1, 0, index),
    ),
  );

  AutoMemoryExtractionService autoService({
    required String characterId,
    required Memory2ExtractionGateway gateway,
    required Memory2StorageService memoryStorage,
    required MemoryExtractionStateService stateService,
    required List<ChatMessage> messages,
    bool enabled = true,
    AutoMemoryLogger? logger,
  }) => AutoMemoryExtractionService(
    characterId: characterId,
    gateway: gateway,
    storage: memoryStorage,
    stateService: stateService,
    messagesLoader: () async => messages,
    settingsLoader: () async => CharacterSettings.genericDefaults().copyWith(
      characterName: '角色',
      autoMemoryEnabled: enabled,
    ),
    userNameLoader: () async => '用户',
    legacyLoader: () async => const [],
    logger: logger,
  );

  test('extractor parse keeps valid source ids and drops unknown sources', () {
    final extractor = Memory2ModelExtractor();
    addTearDown(extractor.dispose);

    final result = extractor.parse(
      '''```json
      {"eventMemories":[
        {"content":"一起看海","sourceMessageIds":["m1","unknown"],"occurredAt":"2026-08-01"},
        {"content":"没有来源","sourceMessageIds":[]}
      ],"userMemories":[
        {"key":"喜欢","value":"咖啡","sourceMessageIds":["m2","unknown"]},
        {"key":"没有来源","value":"","sourceMessageIds":["m1"]}
      ]}
      ```''',
      allowedMessageIds: {'m1', 'm2'},
    );

    expect(result.eventMemories.single.sourceMessageIds, ['m1']);
    expect(result.userMemories.single.sourceMessageIds, ['m2']);
  });

  test('extractor accepts schema without reason importance or confidence', () {
    final extractor = Memory2ModelExtractor();
    addTearDown(extractor.dispose);
    final result = extractor.parse(
      '{"eventMemories":[],"userMemories":[]}',
      allowedMessageIds: const {},
    );
    expect(result.eventMemories, isEmpty);
    expect(result.userMemories, isEmpty);
  });

  test('extractor accepts pure, fenced, plain-fenced, and wrapped JSON', () {
    final extractor = Memory2ModelExtractor();
    addTearDown(extractor.dispose);
    const payload = '{"eventMemories":[],"userMemories":[]}';
    final cases = <String, MemoryExtractionRawResponseShape>{
      payload: MemoryExtractionRawResponseShape.pureJson,
      '```json\n$payload\n```': MemoryExtractionRawResponseShape.fencedJson,
      '```\n$payload\n```': MemoryExtractionRawResponseShape.fencedJson,
      '说明文字\n$payload\n处理完成': MemoryExtractionRawResponseShape.wrappedJson,
    };
    for (final entry in cases.entries) {
      final result = extractor.parse(entry.key, allowedMessageIds: const {});
      expect(result.eventMemories, isEmpty);
      expect(result.userMemories, isEmpty);
      expect(result.rawResponseShape, entry.value);
      expect(result.parseOutcome, 'success');
    }
  });

  test('extractor rejects multiple, missing, and incorrectly typed JSON', () {
    final extractor = Memory2ModelExtractor();
    addTearDown(extractor.dispose);
    void expectRejected(String raw) {
      expect(
        () => extractor.parse(raw, allowedMessageIds: const {}),
        throwsA(isA<MemoryExtractionParseException>()),
      );
    }

    expectRejected(
      '{"eventMemories":[],"userMemories":[]} {"eventMemories":[],"userMemories":[]}',
    );
    expectRejected('{"eventMemories":[]}');
    expectRejected('{"userMemories":[]}');
    expectRejected('{"eventMemories":{},"userMemories":[]}');
    expectRejected('{"eventMemories":[],"userMemories":{}}');
  });

  test(
    'extraction prompt explicitly preserves stable preferences and shared events',
    () {
      final extractor = Memory2ModelExtractor();
      addTearDown(extractor.dispose);
      final request = Memory2ExtractionRequest(
        characterName: '角色',
        userName: '用户',
        messages: const [],
      );
      final system =
          extractor.buildMessages(request).first['content'] as String;
      expect(system, contains('喜欢拿铁，不喜欢美式'));
      expect(system, contains('剧情和 PVE，不喜欢 PVP'));
      expect(system, contains('蓝色绣球'));
      expect(system, contains('不要求是重大人生事件'));
      expect(system, contains('只返回 JSON'));
      final schema = system.substring(
        system.indexOf('{'),
        system.indexOf('}') + 1,
      );
      expect(schema, isNot(contains('reason')));
      expect(schema, isNot(contains('importance')));
      expect(schema, isNot(contains('confidence')));
    },
  );

  test('new extractor includes transcript only once', () {
    final extractor = Memory2ModelExtractor();
    addTearDown(extractor.dispose);
    final request = Memory2ExtractionRequest(
      characterName: '角色',
      userName: '用户',
      messages: [ChatMessage(id: 'unique-id', role: 'user', content: '秘密正文')],
    );
    final messages = extractor.buildMessages(request);
    expect(messages, hasLength(2));
    expect(messages.first['content'], isNot(contains('unique-id')));
    expect(messages.last['content'], contains('unique-id'));
  });

  test(
    'extraction cursor state round-trips through a versioned wrapper',
    () async {
      final service = MemoryExtractionStateService(
        characterId: 'role-a',
        fileProvider: (id) async => File(
          '${directory.path}/$id/${MemoryExtractionStateService.fileName}',
        ),
      );
      final state = MemoryExtractionState(
        characterId: 'other-role',
        lastProcessedMessageId: 'm-42',
        lastProcessedAt: DateTime.utc(2026, 8, 2),
        lastSuccessfulExtractionAt: DateTime.utc(2026, 8, 3),
        lastFailureAt: DateTime.utc(2026, 8, 4),
        lastFailedMessageId: 'm-41',
      );

      await service.save(state);
      final file = File(
        '${directory.path}/role-a/${MemoryExtractionStateService.fileName}',
      );
      final raw = jsonDecode(await file.readAsString()) as Map;
      expect(raw['schemaVersion'], MemoryExtractionStateService.schemaVersion);
      expect((raw['state'] as Map)['characterId'], 'role-a');

      final restored = await service.load();
      expect(restored.characterId, 'role-a');
      expect(restored.lastProcessedMessageId, 'm-42');
      expect(restored.lastProcessedAt, DateTime.utc(2026, 8, 2));
      expect(restored.lastSuccessfulExtractionAt, DateTime.utc(2026, 8, 3));
      expect(restored.lastFailureAt, DateTime.utc(2026, 8, 4));
      expect(restored.lastFailedMessageId, 'm-41');
    },
  );

  test(
    'engine deduplicates events in one batch and merges source ids',
    () async {
      final service = storage('role-a');
      final result = await Memory2Engine(storage: service).apply(
        const MemoryExtractionResult(
          eventMemories: [
            ExtractedEventMemory(content: '一起在海边散步', sourceMessageIds: ['m1']),
            ExtractedEventMemory(
              content: '一起在海边散步并聊到未来',
              sourceMessageIds: ['m1', 'm2'],
            ),
          ],
        ),
        legacyViews: const [],
        now: DateTime.utc(2026, 8, 5),
      );

      final events = await service.loadEventMemories();
      expect(result.addedEvents, 1);
      expect(events, hasLength(1));
      expect(events.single.content, '一起在海边散步并聊到未来');
      expect(events.single.sourceMessageIds, ['m1', 'm2']);
    },
  );

  test(
    'engine updates same active user key and keeps different keys',
    () async {
      final service = storage('role-a');
      await service.upsertUserMemory(
        UserMemory(
          id: 'existing',
          characterId: 'role-a',
          key: '喜欢的饮品',
          value: '茶',
          sourceMessageIds: const ['old-source'],
        ),
      );

      final result = await Memory2Engine(storage: service).apply(
        const MemoryExtractionResult(
          userMemories: [
            ExtractedUserMemory(
              key: '喜欢的饮品',
              value: '咖啡',
              sourceMessageIds: ['new-source'],
            ),
            ExtractedUserMemory(
              key: '休息日',
              value: '喜欢散步',
              sourceMessageIds: ['walk-source'],
            ),
          ],
        ),
        legacyViews: const [],
        now: DateTime.utc(2026, 8, 6),
      );

      final users = await service.loadUserMemories();
      expect(result.addedUsers, 1);
      expect(result.updatedUsers, 1);
      expect(users, hasLength(2));
      final drink = users.firstWhere((item) => item.key == '喜欢的饮品');
      expect(drink.id, 'existing');
      expect(drink.value, '咖啡');
      expect(drink.sourceMessageIds, ['old-source', 'new-source']);
      expect(users.any((item) => item.key == '休息日'), isTrue);
    },
  );

  test('engine does not migrate legacy event or user views', () async {
    final service = storage('role-a');
    final legacy = [
      LegacyMemoryView(
        id: 'legacy-event-view',
        characterId: 'role-a',
        legacySourceId: 'old-event',
        kind: LegacyMemoryKind.event,
        content: '一起在海边散步',
        category: '经历过的事',
        createdAt: DateTime.utc(2026, 8, 1),
        isPinned: true,
        legacyArchived: false,
      ),
      LegacyMemoryView(
        id: 'legacy-user-view',
        characterId: 'role-a',
        legacySourceId: 'old-user',
        kind: LegacyMemoryKind.user,
        content: '喜欢咖啡',
        category: '关于我',
        createdAt: DateTime.utc(2026, 8, 1),
        isPinned: false,
        legacyArchived: false,
      ),
    ];

    await Memory2Engine(storage: service).apply(
      const MemoryExtractionResult(
        eventMemories: [
          ExtractedEventMemory(content: '一起在海边散步', sourceMessageIds: ['m1']),
        ],
        userMemories: [
          ExtractedUserMemory(key: '喜欢', value: '咖啡', sourceMessageIds: ['m2']),
        ],
      ),
      legacyViews: legacy,
      now: DateTime.utc(2026, 8, 7),
    );

    expect(await service.loadEventMemories(), isEmpty);
    expect(await service.loadUserMemories(), isEmpty);
  });

  test(
    'automatic memories retain source ids and pinned state on existing event',
    () async {
      final service = storage('role-a');
      await service.upsertEventMemory(
        EventMemory(
          id: 'pinned-event',
          characterId: 'role-a',
          content: '一起在海边散步',
          sourceMessageIds: const ['old-source'],
          isPinned: true,
          sourceType: MemorySourceType.automatic,
        ),
      );

      await Memory2Engine(storage: service).apply(
        const MemoryExtractionResult(
          eventMemories: [
            ExtractedEventMemory(
              content: '一起在海边散步',
              sourceMessageIds: ['new-source'],
            ),
          ],
        ),
        legacyViews: const [],
        now: DateTime.utc(2026, 8, 8),
      );

      final restored = (await service.loadEventMemories()).single;
      expect(restored.id, 'pinned-event');
      expect(restored.isPinned, isTrue);
      expect(restored.sourceMessageIds, ['old-source', 'new-source']);
    },
  );

  test(
    'auto extraction uses fake gateway after thresholds and advances cursor',
    () async {
      final gateway = _FakeGateway();
      final service = storage('role-a');
      final stateService = MemoryExtractionStateService(
        characterId: 'role-a',
        fileProvider: (id) async => File(
          '${directory.path}/$id/${MemoryExtractionStateService.fileName}',
        ),
      );
      final messages = List<ChatMessage>.generate(
        8,
        (index) => ChatMessage(
          id: 'm${index + 1}',
          role: index.isEven ? 'user' : 'assistant',
          content: '消息 ${index + 1}',
          createdAt: DateTime.utc(2026, 8, 1, 0, index),
        ),
      );
      final extractor = AutoMemoryExtractionService(
        characterId: 'role-a',
        gateway: gateway,
        storage: service,
        stateService: stateService,
        messagesLoader: () async => messages,
        settingsLoader: () async => CharacterSettings.genericDefaults()
            .copyWith(characterName: '角色 A', autoMemoryEnabled: true),
        userNameLoader: () async => '用户',
        legacyLoader: () async => const [],
      );
      addTearDown(extractor.dispose);

      expect(
        await extractor.maybeExtract(now: DateTime.utc(2026, 8, 2)),
        AutoMemoryExtractionOutcome.success,
      );
      expect(gateway.calls, 1);
      expect(
        gateway.request!.messages.map((item) => item.id),
        messages.map((item) => item.id),
      );
      expect((await service.loadEventMemories()).single.sourceMessageIds, [
        'm8',
      ]);
      expect((await stateService.load()).lastProcessedMessageId, 'm8');
    },
  );

  test('below threshold and disabled setting do not call gateway', () async {
    final state = MemoryExtractionStateService(
      characterId: 'role-a',
      fileProvider: (id) async => File('${directory.path}/$id/state.json'),
    );
    final gateway = _FakeGateway();
    final tooSmall = autoService(
      characterId: 'role-a',
      gateway: gateway,
      memoryStorage: storage('role-a'),
      stateService: state,
      messages: batch().take(7).toList(),
    );
    expect(
      await tooSmall.maybeExtract(),
      AutoMemoryExtractionOutcome.insufficientMessages,
    );
    final disabled = autoService(
      characterId: 'role-a',
      gateway: gateway,
      memoryStorage: storage('role-a'),
      stateService: state,
      messages: batch(),
      enabled: false,
    );
    expect(await disabled.maybeExtract(), AutoMemoryExtractionOutcome.disabled);
    expect(gateway.calls, 0);
  });

  test(
    'successful empty result advances once and does not repeat batch',
    () async {
      final state = MemoryExtractionStateService(
        characterId: 'role-a',
        fileProvider: (id) async => File('${directory.path}/$id/state.json'),
      );
      final gateway = _FakeGateway(result: const MemoryExtractionResult());
      final service = autoService(
        characterId: 'role-a',
        gateway: gateway,
        memoryStorage: storage('role-a'),
        stateService: state,
        messages: batch(),
      );
      expect(await service.maybeExtract(), AutoMemoryExtractionOutcome.success);
      expect(
        await service.maybeExtract(),
        AutoMemoryExtractionOutcome.insufficientMessages,
      );
      expect(gateway.calls, 1);
      expect((await state.load()).lastProcessedMessageId, 'm8');
    },
  );

  test('API or parse failure does not advance and enters cooldown', () async {
    for (final error in <Object>[
      StateError('api'),
      const FormatException('json'),
    ]) {
      final id = error is FormatException ? 'parse-role' : 'api-role';
      final state = MemoryExtractionStateService(
        characterId: id,
        fileProvider: (value) async =>
            File('${directory.path}/$value/state.json'),
      );
      final service = autoService(
        characterId: id,
        gateway: _FakeGateway(error: error),
        memoryStorage: storage(id),
        stateService: state,
        messages: batch(prefix: id),
      );
      final now = DateTime.utc(2026, 8, 10);
      expect(
        await service.maybeExtract(now: now),
        AutoMemoryExtractionOutcome.failed,
      );
      expect((await state.load()).lastProcessedMessageId, isNull);
      expect(
        await service.maybeExtract(now: now.add(const Duration(minutes: 1))),
        AutoMemoryExtractionOutcome.coolingDown,
      );
    }
  });

  test(
    'storage failure does not advance cursor or escape to chat caller',
    () async {
      final badDirectory = Directory('${directory.path}/event_memories.json');
      await badDirectory.create();
      final brokenStorage = Memory2StorageService(
        characterId: 'role-a',
        fileProvider: (id, name) async => name == 'event_memories.json'
            ? File(badDirectory.path)
            : File('${directory.path}/$id/$name'),
      );
      final state = MemoryExtractionStateService(
        characterId: 'role-a',
        fileProvider: (id) async => File('${directory.path}/$id/state.json'),
      );
      final service = autoService(
        characterId: 'role-a',
        gateway: _FakeGateway(),
        memoryStorage: brokenStorage,
        stateService: state,
        messages: batch(),
      );
      expect(await service.maybeExtract(), AutoMemoryExtractionOutcome.failed);
      expect((await state.load()).lastProcessedMessageId, isNull);
    },
  );

  test(
    'same character is guarded while different characters are independent',
    () async {
      final blocker = Completer<void>();
      final gateway = _FakeGateway(
        blocker: blocker,
        result: const MemoryExtractionResult(),
      );
      MemoryExtractionStateService state(String id) =>
          MemoryExtractionStateService(
            characterId: id,
            fileProvider: (value) async =>
                File('${directory.path}/$value/state.json'),
          );
      final first = autoService(
        characterId: 'role-a',
        gateway: gateway,
        memoryStorage: storage('role-a'),
        stateService: state('role-a'),
        messages: batch(prefix: 'a'),
      );
      final duplicate = autoService(
        characterId: 'role-a',
        gateway: gateway,
        memoryStorage: storage('role-a'),
        stateService: state('role-a'),
        messages: batch(prefix: 'a'),
      );
      final other = autoService(
        characterId: 'role-b',
        gateway: gateway,
        memoryStorage: storage('role-b'),
        stateService: state('role-b'),
        messages: batch(prefix: 'b'),
      );
      final runningA = first.maybeExtract();
      await Future<void>.delayed(Duration.zero);
      expect(
        await duplicate.maybeExtract(),
        AutoMemoryExtractionOutcome.alreadyRunning,
      );
      final runningB = other.maybeExtract();
      for (var attempt = 0; attempt < 100 && gateway.calls < 2; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(gateway.calls, 2);
      blocker.complete();
      expect(await runningA, AutoMemoryExtractionOutcome.success);
      expect(await runningB, AutoMemoryExtractionOutcome.success);
      expect((await state('role-a').load()).lastProcessedMessageId, 'a8');
      expect((await state('role-b').load()).lastProcessedMessageId, 'b8');
    },
  );

  test('logs contain counts and ids but not chat text', () async {
    final logs = <String>[];
    final messages = batch();
    messages[0] = ChatMessage(
      id: 'm1',
      role: 'user',
      content: 'TOP_SECRET_CHAT_TEXT',
      createdAt: messages[0].createdAt,
    );
    final state = MemoryExtractionStateService(
      characterId: 'safe-role',
      fileProvider: (id) async => File('${directory.path}/$id/state.json'),
    );
    final service = autoService(
      characterId: 'safe-role',
      gateway: _FakeGateway(result: const MemoryExtractionResult()),
      memoryStorage: storage('safe-role'),
      stateService: state,
      messages: messages,
      logger: logs.add,
    );
    await service.maybeExtract();
    expect(logs.join('\n'), isNot(contains('TOP_SECRET_CHAT_TEXT')));
    expect(logs.join('\n'), contains('characterId=safe-role'));
    expect(logs.join('\n'), contains('batchCount=8'));
  });

  test(
    'automatic extraction never writes legacy memory or archive files',
    () async {
      final state = MemoryExtractionStateService(
        characterId: 'role-a',
        fileProvider: (id) async => File('${directory.path}/$id/state.json'),
      );
      final service = autoService(
        characterId: 'role-a',
        gateway: _FakeGateway(result: const MemoryExtractionResult()),
        memoryStorage: storage('role-a'),
        stateService: state,
        messages: batch(),
      );
      await service.maybeExtract();
      expect(
        File('${directory.path}/role-a/memories.json').existsSync(),
        isFalse,
      );
      expect(
        File('${directory.path}/role-a/archive.json').existsSync(),
        isFalse,
      );
    },
  );
}
