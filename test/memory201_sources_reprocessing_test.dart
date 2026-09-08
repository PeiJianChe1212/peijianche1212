import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/models/memory_extraction_result.dart';
import 'package:peijianche_app/models/memory_extraction_state.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/services/auto_memory_extraction_service.dart';
import 'package:peijianche_app/services/chat_storage_service.dart';
import 'package:peijianche_app/services/event_memory_lifecycle_service.dart';
import 'package:peijianche_app/services/memory2_chat_context_builder.dart';
import 'package:peijianche_app/services/memory2_engine.dart';
import 'package:peijianche_app/services/memory2_extractor.dart';
import 'package:peijianche_app/services/memory2_retriever.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';
import 'package:peijianche_app/services/memory_center_controller.dart';
import 'package:peijianche_app/services/memory_content_boundary.dart';
import 'package:peijianche_app/services/memory_extraction_state_service.dart';
import 'package:peijianche_app/services/memory_source_resolver.dart';

class _Gateway implements Memory2ExtractionGateway {
  MemoryExtractionResult result = const MemoryExtractionResult();
  Object? error;
  Completer<void>? gate;
  int calls = 0;
  Memory2ExtractionRequest? request;
  @override
  Future<MemoryExtractionResult> extract(Memory2ExtractionRequest value) async {
    calls++;
    request = value;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temp;
  late Memory2StorageService storage;
  late MemoryExtractionStateService state;
  late _Gateway gateway;
  late List<ChatMessage> messages;
  late List<String> logs;
  final now = DateTime.utc(2026, 9, 4);
  ChatMessage user(String text, {String id = 'u', DateTime? time}) =>
      ChatMessage(id: id, role: 'user', content: text, createdAt: time ?? now);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('memory201_sources_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => temp.path);
    storage = Memory2StorageService(
      characterId: 'c',
      fileProvider: (_, name) async => File('${temp.path}/$name'),
    );
    state = MemoryExtractionStateService(
      characterId: 'c',
      fileProvider: (_) async => File('${temp.path}/state.json'),
    );
    gateway = _Gateway();
    messages = [user('我不吃香菜')];
    logs = [];
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temp.delete(recursive: true);
  });
  AutoMemoryExtractionService service() => AutoMemoryExtractionService(
    characterId: 'c',
    storage: storage,
    stateService: state,
    gateway: gateway,
    messagesLoader: () async => messages,
    legacyLoader: () async => [],
    userNameLoader: () async => '用户',
    logger: logs.add,
    settingsLoader: () async =>
        CharacterSettings.genericDefaults().copyWith(autoMemoryEnabled: true),
  );
  MemorySourceResolver resolver() => MemorySourceResolver(
    characterId: 'c',
    messagesLoader: () async => messages,
  );
  void userResult({String value = '不吃香菜'}) {
    gateway.result = MemoryExtractionResult(
      userMemories: [
        ExtractedUserMemory(
          key: '忌口',
          value: value,
          sourceMessageIds: const ['u'],
        ),
      ],
    );
  }

  void eventResult() {
    gateway.result = const MemoryExtractionResult(
      eventMemories: [
        ExtractedEventMemory(content: '一起讨论了海边散步', sourceMessageIds: ['u']),
      ],
    );
  }

  group('Source', () {
    test(
      'Event resolves existing source with time type and short preview',
      () async {
        final event = EventMemory(
          id: 'e',
          characterId: 'c',
          content: '记忆',
          sourceMessageIds: ['u'],
        );
        final source = (await resolver().resolve(
          event.sourceMessageIds,
        )).single;
        expect(source.available, isTrue);
        expect(source.createdAt, now);
        expect(source.type, MessageType.text);
        expect(source.preview, '我不吃香菜');
      },
    );
    test(
      'User source order is stable and duplicates do not multiply',
      () async {
        messages.add(user('第二条', id: 'b'));
        final memory = UserMemory(
          id: 'm',
          characterId: 'c',
          key: 'k',
          value: 'v',
          sourceMessageIds: ['b', 'u', 'b'],
        );
        expect(
          (await resolver().resolve(
            memory.sourceMessageIds,
          )).map((s) => s.messageId),
          ['b', 'u'],
        );
      },
    );
    test(
      'missing and recalled messages are unavailable without fabricated metadata',
      () async {
        messages[0] = messages[0].copyWith(
          messageStatus: MessageStatus.recalled,
        );
        final sources = await resolver().resolve(['missing', 'u']);
        expect(
          sources.every(
            (s) => !s.available && s.preview.isEmpty && s.type == null,
          ),
          isTrue,
        );
      },
    );
    test(
      'manual and legacy-only references never trigger chat lookup',
      () async {
        var reads = 0;
        final r = MemorySourceResolver(
          characterId: 'c',
          messagesLoader: () async {
            reads++;
            return messages;
          },
        );
        final manual = EventMemory(id: 'e', characterId: 'c', content: '手动');
        final legacy = UserMemory(
          id: 'm',
          characterId: 'c',
          key: '',
          value: '旧记忆',
          legacySourceId: 'u',
        );
        expect(await r.resolve(manual.sourceMessageIds), isEmpty);
        expect(await r.resolve(legacy.sourceMessageIds), isEmpty);
        expect(reads, 0);
      },
    );
    test(
      'clear real chat removes sources but leaves Memory bytes unchanged',
      () async {
        final chat = ChatStorageService(characterId: 'c');
        await chat.saveMessages(messages);
        await storage.saveEventMemories([
          EventMemory(
            id: 'e',
            characterId: 'c',
            content: '普通',
            sourceMessageIds: ['u'],
          ),
        ]);
        final before = await File(
          '${temp.path}/event_memories.json',
        ).readAsString();
        final r = MemorySourceResolver(characterId: 'c');
        expect((await r.resolve(['u'])).single.available, isTrue);
        await chat.clearMessages();
        expect((await r.resolve(['u'])).single.available, isFalse);
        expect(
          await File('${temp.path}/event_memories.json').readAsString(),
          before,
        );
      },
    );
    test(
      'existing image uses original path and bounded AI description',
      () async {
        final image = File('${temp.path}/original.png');
        await image.writeAsBytes([1]);
        messages = [
          ChatMessage(
            id: 'pic',
            role: 'user',
            content: '配文',
            type: MessageType.image,
            metadata: {'imagePath': image.path, 'visionDescription': '猫' * 500},
          ),
        ];
        final source = (await resolver().resolve(['pic'])).single;
        expect(source.imagePath, image.path);
        expect(source.imageMissing, isFalse);
        expect(
          source.visionPreview.length,
          MemorySourceResolver.previewCharacters,
        );
        expect(await temp.list().length, 1);
      },
    );
    test(
      'deleted image retains caption and description with missing image flag',
      () async {
        messages = [
          ChatMessage(
            id: 'pic',
            role: 'user',
            content: '我的照片',
            type: MessageType.image,
            metadata: {
              'imagePath': '${temp.path}/gone.png',
              'visionDescription': '有一只猫',
            },
          ),
        ];
        final source = (await resolver().resolve(['pic'])).single;
        expect(source.available, isTrue);
        expect(source.imageMissing, isTrue);
        expect(source.imagePath, isNull);
        expect(source.preview, '我的照片');
      },
    );
    test('source read failure safely degrades', () async {
      final r = MemorySourceResolver(
        characterId: 'c',
        messagesLoader: () async => throw StateError('private sentinel'),
      );
      expect((await r.resolve(['u'])).single.available, isFalse);
    });
  });

  group('Content boundary', () {
    final external = {
      '引用朋友': '朋友说她最喜欢草莓。',
      '新闻': '新闻报道称咖啡很受欢迎。',
      '长文章': '以下文章：${'咖啡历史资料。' * 400}',
      'Dart': "import 'dart:io'; void main() { print('Alice'); }",
      'Python': "def profile():\n    return {'name': 'Alice'}",
      'Flutter':
          'class Example extends StatelessWidget { Widget build(context) {} }',
      '角色设定': '创建角色，虚构人物小林喜欢草莓，生日六月一日。',
      '开发资料': '系统提示词：你是一个喜欢咖啡的助手。',
    };
    for (final entry in external.entries) {
      test(
        '${entry.key} source context forbids a fabricated user preference',
        () async {
          messages = [user(entry.value)];
          userResult(value: '喜欢草莓');
          expect(
            await service().reprocess(['u']),
            MemoryReprocessingOutcome.empty,
          );
          expect(await storage.loadUserMemories(), isEmpty);
          expect(gateway.calls, 1);
          final extractor = Memory2ModelExtractor();
          addTearDown(extractor.dispose);
          final prompt = extractor.buildMessages(gateway.request!);
          final record = jsonDecode(prompt.last['content'] as String) as Map;
          expect(record['context'], isNot(contains('用户消息（是否为本人陈述须依语境）')));
          expect(prompt.first['content'], contains('不能变成用户'));
        },
      );
    }
    test(
      'very short personal fact is eligible independent of length',
      () async {
        userResult();
        expect(
          await service().reprocess(['u']),
          MemoryReprocessingOutcome.success,
        );
        expect((await storage.loadUserMemories()).single.value, '不吃香菜');
      },
    );
    test('image AI description alone never establishes ownership', () async {
      messages = [
        ChatMessage(
          id: 'u',
          role: 'user',
          content: '',
          type: MessageType.image,
          metadata: {'visionDescription': '一只猫坐在沙发上'},
        ),
      ];
      userResult(value: '用户养了一只猫');
      expect(await service().reprocess(['u']), MemoryReprocessingOutcome.empty);
      final record =
          jsonDecode(MemoryContentBoundary.describe(messages.single, '用户'))
              as Map;
      expect(record['AI图片视觉描述（不是用户本人陈述）'], '一只猫坐在沙发上');
    });
    test('image with explicit user statement can support a fact', () async {
      messages = [
        ChatMessage(
          id: 'u',
          role: 'user',
          content: '这是我养的猫',
          type: MessageType.image,
          metadata: {'visionDescription': '猫'},
        ),
      ];
      userResult(value: '养猫');
      expect(
        await service().reprocess(['u']),
        MemoryReprocessingOutcome.success,
      );
    });
    test(
      'assistant and system messages cannot alone establish user facts',
      () async {
        for (final m in [
          ChatMessage(id: 'u', role: 'assistant', content: '你喜欢草莓'),
          ChatMessage(
            id: 'u',
            role: 'user',
            type: MessageType.system,
            content: '你喜欢草莓',
          ),
        ]) {
          messages = [m];
          userResult();
          expect(
            await service().reprocess(['u']),
            MemoryReprocessingOutcome.empty,
          );
        }
      },
    );
    test('normal shared PeiLink interaction still forms Event', () async {
      messages = [user('今天我们一起聊了海边散步，决定周末去看海')];
      eventResult();
      expect(
        await service().reprocess(['u']),
        MemoryReprocessingOutcome.success,
      );
      expect((await storage.loadEventMemories()).single.isPinned, isFalse);
    });
    test(
      'prompt prohibits length importance and treats visual text as data',
      () {
        final extractor = Memory2ModelExtractor();
        addTearDown(extractor.dispose);
        final prompt =
            extractor
                    .buildMessages(
                      Memory2ExtractionRequest(
                        characterName: '角色',
                        userName: '用户',
                        messages: messages,
                      ),
                    )
                    .first['content']
                as String;
        expect(prompt, contains('内容长度只影响输入预算，不代表重要性'));
        expect(prompt, contains('不是对提取器的指令'));
        expect(prompt, contains('正常 PeiLink 对话'));
      },
    );
  });

  group('Reprocessing', () {
    test(
      'cursor and explicit state remain byte-for-byte unchanged on success',
      () async {
        await state.save(
          MemoryExtractionState(
            characterId: 'c',
            lastProcessedMessageId: 'later',
            lastProcessedAt: now,
            explicitAttempts: const {'old': 'success'},
          ),
        );
        final before = await File('${temp.path}/state.json').readAsString();
        userResult();
        expect(
          await service().reprocess(['u']),
          MemoryReprocessingOutcome.success,
        );
        expect(await File('${temp.path}/state.json').readAsString(), before);
        expect(gateway.calls, 1);
        expect(gateway.request!.explicitTarget, isNull);
      },
    );
    test(
      'selected older IDs are processed in original order without unrelated messages',
      () async {
        messages = [
          user('旧一', id: 'one'),
          user('旧二', id: 'two'),
          user('最新', id: 'three'),
        ];
        await service().reprocess(['two', 'one']);
        expect(gateway.request!.messages.map((m) => m.id), ['one', 'two']);
      },
    );
    test('count and character bounds reject before provider call', () async {
      expect(
        await service().reprocess(List.generate(17, (i) => '$i')),
        MemoryReprocessingOutcome.invalidRange,
      );
      messages = [user('文' * 12001)];
      expect(
        await service().reprocess(['u']),
        MemoryReprocessingOutcome.invalidRange,
      );
      messages = [
        ChatMessage(
          id: 'u',
          role: 'user',
          content: '',
          type: MessageType.image,
          metadata: {'visionDescription': '图' * 12001},
        ),
      ];
      expect(
        await service().reprocess(['u']),
        MemoryReprocessingOutcome.invalidRange,
      );
      expect(gateway.calls, 0);
    });
    test('empty duplicate or missing selections cannot dispatch', () async {
      expect(
        await service().reprocess([]),
        MemoryReprocessingOutcome.invalidRange,
      );
      expect(
        await service().reprocess(['u', 'u']),
        MemoryReprocessingOutcome.invalidRange,
      );
      expect(
        await service().reprocess(['gone']),
        MemoryReprocessingOutcome.sourceUnavailable,
      );
      expect(gateway.calls, 0);
    });
    test(
      'empty leaves files untouched and creates no Pending or Memory',
      () async {
        expect(
          await service().reprocess(['u']),
          MemoryReprocessingOutcome.empty,
        );
        expect(await temp.list().length, 0);
      },
    );
    test(
      'provider failure preserves memory and cursor and allows a later manual retry',
      () async {
        await storage.saveUserMemories([
          UserMemory(
            id: 'm',
            characterId: 'c',
            key: '忌口',
            value: '不吃香菜',
            userConfirmed: true,
          ),
        ]);
        await state.save(
          const MemoryExtractionState(
            characterId: 'c',
            lastProcessedMessageId: 'done',
          ),
        );
        final before = await File(
          '${temp.path}/user_memories.json',
        ).readAsString();
        final cursor = await File('${temp.path}/state.json').readAsString();
        gateway.error = StateError('private source text');
        expect(
          await service().reprocess(['u']),
          MemoryReprocessingOutcome.failed,
        );
        expect(
          await File('${temp.path}/user_memories.json').readAsString(),
          before,
        );
        expect(await File('${temp.path}/state.json').readAsString(), cursor);
        gateway.error = null;
        userResult();
        expect(
          await service().reprocess(['u']),
          MemoryReprocessingOutcome.success,
        );
        expect(gateway.calls, 2);
      },
    );
    test(
      'duplicate Event and User do not multiply or lose protection',
      () async {
        await storage.saveEventMemories([
          EventMemory(
            id: 'e',
            characterId: 'c',
            content: '一起讨论了海边散步',
            isPinned: true,
            sourceMessageIds: ['u'],
          ),
        ]);
        eventResult();
        await service().reprocess(['u']);
        expect((await storage.loadEventMemories()).single.isPinned, isTrue);
        await storage.saveUserMemories([
          UserMemory(
            id: 'm',
            characterId: 'c',
            key: '忌口',
            value: '不吃香菜',
            userConfirmed: true,
          ),
        ]);
        userResult();
        await service().reprocess(['u']);
        expect((await storage.loadUserMemories()).single.userConfirmed, isTrue);
        userResult(value: '喜欢香菜');
        await service().reprocess(['u']);
        expect((await storage.loadUserMemories()).single.value, '不吃香菜');
      },
    );
    test('old correction cannot retire a newer protected version', () async {
      await storage.saveUserMemories([
        UserMemory(
          id: 'new',
          characterId: 'c',
          key: '忌口',
          value: '不吃香菜',
          createdAt: now,
          userConfirmed: true,
        ),
      ]);
      messages = [
        user('以前不吃香菜，现在更喜欢香菜', time: now.subtract(const Duration(days: 2))),
      ];
      gateway.result = const MemoryExtractionResult(
        userMemories: [
          ExtractedUserMemory(
            key: '忌口',
            value: '喜欢香菜',
            sourceMessageIds: ['u'],
            supersedesId: 'new',
            changeEvidence: '以前不吃香菜，现在更喜欢香菜',
          ),
        ],
      );
      await service().reprocess(['u']);
      expect((await storage.loadUserMemories()).single.id, 'new');
    });
    test('reprocessing respects existing role lock', () async {
      gateway.gate = Completer<void>();
      final first = service().reprocess(['u']);
      while (gateway.calls == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(
        await service().reprocess(['u']),
        MemoryReprocessingOutcome.alreadyRunning,
      );
      gateway.gate!.complete();
      await first;
      expect(gateway.calls, 1);
    });
    test('selection view is limited to latest 100', () async {
      messages = List.generate(120, (i) => user('消息$i', id: '$i'));
      final controller = MemoryCenterController(
        characterId: 'c',
        messagesLoader: () async => messages,
      );
      final selection = await controller.loadReprocessingMessages();
      expect(selection.length, 100);
      expect(selection.first.id, '20');
      expect(selection.last.id, '119');
    });
    test('logs contain counts not source prompt or visual contents', () async {
      messages = [user('我喜欢私密哨兵')];
      userResult(value: '私密记忆正文');
      await service().reprocess(['u']);
      expect(logs.join(), contains('count=1'));
      expect(logs.join(), isNot(contains('私密')));
    });
  });

  group('Experience', () {
    test(
      'explicit-important retention survives later ordinary reprocessing',
      () async {
        messages = [user('这个对我很重要，你一定要记住，我不吃香菜。')];
        userResult();
        expect(
          await service().maybeExtract(),
          AutoMemoryExtractionOutcome.success,
        );
        expect((await storage.loadUserMemories()).single.userConfirmed, isTrue);
        userResult(value: '吃香菜');
        await service().reprocess(['u']);
        expect((await storage.loadUserMemories()).single.value, '不吃香菜');
      },
    );
    test(
      'source lookup does not prevent ordinary 30 60 90 forgetting',
      () async {
        final event = EventMemory(
          id: 'e',
          characterId: 'c',
          content: '普通经历',
          sourceMessageIds: ['u'],
          createdAt: now,
        );
        await storage.saveEventMemories([event]);
        await resolver().resolve(event.sourceMessageIds);
        final lifecycle = EventMemoryLifecycleService(
          characterId: 'c',
          storage: storage,
        );
        for (final entry in {
          30: EventMemoryStatus.fading,
          60: EventMemoryStatus.pendingForget,
          90: EventMemoryStatus.forgotten,
        }.entries) {
          await lifecycle.refresh(now: now.add(Duration(days: entry.key)));
          expect(
            (await storage.loadEventMemories()).single.status,
            entry.value,
          );
        }
      },
    );
    test(
      'current and historic recall keep separate sources despite stale Summary',
      () async {
        messages = [
          user('我喜欢咖啡', id: 'a', time: now.subtract(const Duration(days: 10))),
          user('以前喜欢咖啡，现在更喜欢茶', id: 'b'),
        ];
        await storage.saveUserMemories([
          UserMemory(
            id: 'old',
            characterId: 'c',
            key: '喜欢的饮品',
            value: '咖啡',
            sourceMessageIds: ['a'],
            createdAt: now.subtract(const Duration(days: 9)),
          ),
        ]);
        await Memory2Engine(storage: storage).apply(
          const MemoryExtractionResult(
            userMemories: [
              ExtractedUserMemory(
                key: '喜欢的饮品',
                value: '茶',
                sourceMessageIds: ['b'],
                supersedesId: 'old',
                changeEvidence: '以前喜欢咖啡，现在更喜欢茶',
              ),
            ],
          ),
          legacyViews: [],
          sourceMessages: messages,
          now: now,
        );
        await storage.saveMemorySummary(
          const MemorySummary(characterId: 'c', generatedText: '喜欢咖啡'),
        );
        final versions = await storage.loadUserMemories();
        expect(
          (await resolver().resolve(
            versions.first.sourceMessageIds,
          )).single.preview,
          '我喜欢咖啡',
        );
        expect(
          (await resolver().resolve(
            versions.last.sourceMessageIds,
          )).single.preview,
          '以前喜欢咖啡，现在更喜欢茶',
        );
        final r = Memory2Retriever(
          characterId: 'c',
          storage: storage,
          lifecycle: EventMemoryLifecycleService(
            characterId: 'c',
            storage: storage,
          ),
          legacyLoader: () async => [],
        );
        final current = await r.retrieve(currentMessage: '现在喜欢什么饮品', now: now);
        expect(current.selectedUserMemories.single.value, '茶');
        expect(current.selectedHistoricalUserMemories, isEmpty);
        final history = await r.retrieve(
          currentMessage: '我以前是不是喜欢咖啡',
          now: now,
        );
        expect(history.selectedHistoricalUserMemories.single.value, '咖啡');
        expect(
          Memory2ChatContextBuilder.build(
            retrieval: current,
            characterUserProfile: const CharacterUserProfile(characterId: 'c'),
          ),
          contains('当前 active 用户事实优先于长期汇总'),
        );
        userResult();
        await service().reprocess(['b']);
        final after = await storage.loadUserMemories();
        expect(after.first.supersededById, versions.last.id);
      },
    );
  });
}
