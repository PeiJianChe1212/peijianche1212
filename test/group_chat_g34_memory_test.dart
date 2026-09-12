import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/models/group_memory_event.dart';
import 'package:peijianche_app/models/group_message.dart';
import 'package:peijianche_app/services/group_memory_extractor.dart';
import 'package:peijianche_app/services/group_memory_service.dart';
import 'package:peijianche_app/services/group_memory_storage_service.dart';

/// Phase G3.4 targeted coverage: lightweight, speaker-attributed group memory.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('group_g34_memory_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  GroupMemoryStorageService groupStorage(String groupId) =>
      GroupMemoryStorageService(
        groupId: groupId,
        fileProvider: (id, fileName) async =>
            File('${directory.path}/group_chats/$id/$fileName'),
      );

  GroupMessage message(
    String id,
    GroupSenderType senderType,
    String senderId,
    String content, {
    String groupId = 'g1',
    DateTime? at,
    List<String> mentions = const [],
  }) => GroupMessage(
    id: id,
    groupId: groupId,
    senderType: senderType,
    senderId: senderId,
    content: content,
    createdAt: at ?? DateTime.utc(2026, 9, 1, 10),
    mentionedMemberIds: mentions,
  );

  GroupMemoryService service(
    String groupId,
    List<GroupMessage> messages, {
    String groupName = '旅行群',
    Map<String, String> names = const {'a': 'A', 'b': 'B'},
  }) => GroupMemoryService(
    groupId: groupId,
    groupName: groupName,
    storage: groupStorage(groupId),
    messagesLoader: (_) async => messages,
    namesLoader: (_) async => names,
    logger: (_) {},
  );

  test('1. 用户重要事实保留 speaker=user', () {
    final events = const GroupMemoryExtractor().extract(
      groupId: 'g1',
      messages: [
        message(
          'm1',
          GroupSenderType.user,
          'user',
          '我下个月准备去塞尔维亚，这次只带一个行李箱',
        ),
      ],
    );

    expect(events, hasLength(1));
    expect(events.single.speakerIds, ['user']);
    expect(events.single.content, startsWith('用户提到：'));
    expect(events.single.content, contains('塞尔维亚'));
    expect(events.single.sourceMessageIds, ['m1']);
  });

  test('2. A 说的内容不会记成用户说的', () {
    final events = const GroupMemoryExtractor().extract(
      groupId: 'g1',
      senderNames: const {'a': 'A'},
      messages: [
        message(
          'm2',
          GroupSenderType.character,
          'a',
          '你不是最怕行李装多了吗，我记得你以前出门只带很少的东西',
        ),
      ],
    );

    expect(events, hasLength(1));
    expect(events.single.speakerIds, ['a']);
    expect(events.single.content, startsWith('A说：'));
    expect(events.single.content, isNot(contains('用户')));
  });

  test('3. 多人事件保留 participants', () {
    final events = const GroupMemoryExtractor().extract(
      groupId: 'g1',
      messages: [
        message(
          'm3',
          GroupSenderType.user,
          'user',
          '我打算下个月去塞尔维亚，A 和 B 到时候一起出发',
          mentions: ['a', 'b'],
        ),
      ],
    );

    expect(events, hasLength(1));
    expect(events.single.participants, containsAll(['user', 'a', 'b']));
    expect(events.single.speakerIds, ['user']);
  });

  test('4. 普通 hello/哈哈/在吗 允许 0 memory', () {
    final events = const GroupMemoryExtractor().extract(
      groupId: 'g1',
      messages: [
        message('m1', GroupSenderType.user, 'user', '在吗'),
        message('m2', GroupSenderType.character, 'a', '哈哈'),
        message('m3', GroupSenderType.user, 'user', 'hello'),
        message('m4', GroupSenderType.character, 'b', '嗯嗯'),
        message('m5', GroupSenderType.user, 'user', '收到'),
        message('m6', GroupSenderType.character, 'a', '嘿嘿嘿'),
      ],
    );

    expect(events, isEmpty);
  });

  test('5. 同一消息区间不会重复提取', () async {
    final messages = [
      message(
        'm1',
        GroupSenderType.user,
        'user',
        '我下个月准备去塞尔维亚，这次只带一个行李箱',
      ),
      for (var index = 2; index <= 6; index++)
        message('m$index', GroupSenderType.character, 'a', '哈哈'),
    ];
    final extractor = service('g1', messages);

    expect(
      await extractor.maybeExtract(now: DateTime.utc(2026, 9, 1, 12)),
      GroupMemoryExtractionOutcome.success,
    );
    expect(
      await extractor.maybeExtract(now: DateTime.utc(2026, 9, 1, 12, 5)),
      GroupMemoryExtractionOutcome.insufficientMessages,
    );

    final stored = await groupStorage('g1').loadEvents();
    expect(stored, hasLength(1));
    expect(stored.single.content, contains('塞尔维亚'));
  });

  test('6. 群聊公共记忆不会混入角色私人 CharacterUserProfile', () async {
    final privateDirectory = Directory('${directory.path}/characters/c1');
    await privateDirectory.create(recursive: true);
    final privateProfile = File('${privateDirectory.path}/user_persona.json');
    await privateProfile.writeAsString(
      jsonEncode({'characterId': 'c1', 'description': '用户有一个私密秘密'}),
    );

    final messages = [
      message(
        'm1',
        GroupSenderType.user,
        'user',
        '我下个月准备去塞尔维亚，这次只带一个行李箱',
      ),
      for (var index = 2; index <= 6; index++)
        message('m$index', GroupSenderType.character, 'a', '哈哈'),
    ];
    await service('g1', messages).maybeExtract();

    final stored = await groupStorage('g1').loadEvents();
    expect(stored, hasLength(1));
    expect(stored.single.content, isNot(contains('秘密')));
    // Private profile stays untouched and is never copied into group memory.
    expect(await privateProfile.readAsString(), contains('私密秘密'));
  });

  test('7. A 的私人 Memory 不会自动变成 group memory', () async {
    final privateMemory = File(
      '${directory.path}/characters/a/event_memories.json',
    );
    await privateMemory.parent.create(recursive: true);
    await privateMemory.writeAsString(
      jsonEncode({
        'schemaVersion': 2,
        'items': [
          {
            'id': 'private-1',
            'characterId': 'a',
            'content': 'A 私下知道的秘密',
            'createdAt': DateTime.utc(2026, 9, 1).toIso8601String(),
            'updatedAt': DateTime.utc(2026, 9, 1).toIso8601String(),
            'sourceMessageIds': ['private-message'],
            'status': EventMemoryStatus.active.name,
            'recallCount': 0,
            'isPinned': false,
            'sourceType': 'automatic',
          },
        ],
      }),
    );

    final stored = await groupStorage('g1').loadEvents();
    expect(stored, isEmpty);
    expect(
      stored.any((item) => item.content.contains('秘密')),
      isFalse,
    );
  });

  test('8. retrieval 只返回少量相关群聊记忆', () async {
    final storage = groupStorage('g1');
    final now = DateTime.utc(2026, 9, 2);
    await storage.appendEvents(
      [
        for (final text in [
          '用户提到：我下个月准备去塞尔维亚',
          '用户提到：塞尔维亚三月还是很冷，要多带衣服',
          'A说：塞尔维亚的行程还没定下来',
          '用户提到：塞尔维亚的住宿已经订好了',
          '用户提到：周末要去看篮球比赛',
        ])
          GroupMemoryEvent(
            id: 'e_${text.hashCode}',
            groupId: 'g1',
            content: text,
            sourceMessageIds: ['s_${text.hashCode}'],
            createdAt: now,
          ),
      ],
      now: now,
    );

    final retrieval = await GroupMemoryService(
      groupId: 'g1',
      groupName: '旅行群',
      storage: storage,
      logger: (_) {},
    ).retrieve(currentMessage: '塞尔维亚的天气怎么样', now: now);

    expect(retrieval.events, isNotEmpty);
    expect(retrieval.events.length, lessThanOrEqualTo(2));
    expect(
      retrieval.events.every((item) => item.content.contains('塞尔维亚')),
      isTrue,
    );
    expect(retrieval.contextText, contains('群聊共同经历'));
    expect(retrieval.contextText, contains('公开'));
    expect(retrieval.contextText, contains('不是任何人的私聊记忆'));
  });

  test('9. 不同 groupId 的群聊记忆隔离', () async {
    final g1 = groupStorage('g1');
    final g2 = groupStorage('g2');
    await g1.appendEvents([
      GroupMemoryEvent(
        id: 'e1',
        groupId: 'g1',
        content: '用户提到：我下个月准备去塞尔维亚',
        sourceMessageIds: const ['m1'],
      ),
    ]);

    expect(await g1.loadEvents(), hasLength(1));
    expect(await g2.loadEvents(), isEmpty);

    // A misplaced row from another group must not be adopted.
    final misplaced = File(
      '${directory.path}/group_chats/g2/group_memories.json',
    );
    await misplaced.parent.create(recursive: true);
    await misplaced.writeAsString(
      jsonEncode({
        'schemaVersion': 2,
        'items': [
          EventMemory(
            id: 'foreign',
            characterId: 'group:g1',
            content: '用户提到：g1 的事',
            metadata: const {'scope': 'group_chat', 'groupId': 'g1'},
          ).toJson(),
        ],
      }),
    );
    expect(await g2.loadEvents(), isEmpty);
  });

  test('10. 旧群聊没有新记忆数据时仍能正常读取', () async {
    final storage = groupStorage('legacy_group');
    expect(await storage.loadEvents(), isEmpty);

    final retrieval = await GroupMemoryService(
      groupId: 'legacy_group',
      storage: storage,
      logger: (_) {},
    ).retrieve(currentMessage: '我们之前聊过什么');
    expect(retrieval.events, isEmpty);
    expect(retrieval.contextText, isEmpty);

    // Corrupt/unknown data also degrades to an empty read instead of throwing.
    final file = File(
      '${directory.path}/group_chats/legacy_group/group_memories.json',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('{not-json');
    expect(await storage.loadEvents(), isEmpty);
  });
}
