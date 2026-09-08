import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/services/event_memory_lifecycle_service.dart';
import 'package:peijianche_app/services/memory2_chat_context_builder.dart';
import 'package:peijianche_app/services/memory2_retriever.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';
import 'package:peijianche_app/services/user_memory_key_aliases.dart';

void main() {
  late Directory root;
  late Memory2StorageService storage;
  late Memory2Retriever retriever;
  final now = DateTime.utc(2026, 9, 4);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('memory201_alias_');
    storage = Memory2StorageService(
      characterId: 'rc',
      fileProvider: (id, name) async => File('${root.path}/$id/$name'),
    );
    retriever = Memory2Retriever(
      characterId: 'rc',
      storage: storage,
      lifecycle: EventMemoryLifecycleService(
        characterId: 'rc',
        storage: storage,
      ),
      legacyLoader: () async => [],
      logger: (_) {},
    );
  });
  tearDown(() => root.delete(recursive: true));

  UserMemory fact(String id, String key, String value) => UserMemory(
    id: id,
    characterId: 'rc',
    key: key,
    value: value,
    createdAt: now,
  );

  for (final entry in <(String, String)>[
    ('favorite_color', '我现在最喜欢什么颜色？'),
    ('favorite_color', "What's my favorite color?"),
    ('最喜欢的颜色', '我现在最喜欢什么颜色？'),
    ('Favorite-Color', '我的颜色偏好是什么？'),
    ('favorite_food', '我喜欢吃什么？'),
    ('favorite_drink', '我喜欢喝什么？'),
    ('喜欢的饮品', '我喜欢喝什么？'),
    ('game_preference', '我喜欢什么游戏？'),
    ('hobbies', '我的兴趣爱好是什么？'),
    ('dietary_restriction', '我有什么忌口？'),
    ('work_habits', '我的工作习惯是什么？'),
    ('preferred_name', '应该怎么称呼我？'),
  ]) {
    test('short value recalled for ${entry.$1}: ${entry.$2}', () async {
      await storage.saveUserMemories([fact('b', entry.$1, '绿色')]);
      final result = await retriever.retrieve(
        currentMessage: entry.$2,
        now: now,
      );
      expect(result.selectedUserMemories.map((m) => m.id), ['b']);
      expect(result.selectedHistoricalUserMemories, isEmpty);
    });
  }

  Future<void> history() async {
    await storage.saveUserMemories([
      UserMemory(
        id: 'a',
        characterId: 'rc',
        key: 'favorite_color',
        value: '橙色',
        status: UserMemoryStatus.superseded,
        supersededById: 'b',
        sourceMessageIds: ['old-source'],
        createdAt: now,
      ),
      UserMemory(
        id: 'b',
        characterId: 'rc',
        key: 'favorite_color',
        value: '绿色',
        mergedFromIds: ['a'],
        sourceMessageIds: ['change-source'],
        userConfirmed: true,
        createdAt: now,
      ),
    ]);
    await storage.saveMemorySummary(
      const MemorySummary(characterId: 'rc', generatedText: '用户喜欢橙色'),
    );
  }

  test('active short value is injected despite stale Summary', () async {
    await history();
    final result = await retriever.retrieve(
      currentMessage: '我现在最喜欢什么颜色？',
      now: now,
    );
    expect(result.selectedUserMemories.map((m) => m.id), ['b']);
    expect(result.selectedHistoricalUserMemories, isEmpty);
    final context = Memory2ChatContextBuilder.build(
      retrieval: result,
      characterUserProfile: const CharacterUserProfile(characterId: 'rc'),
    );
    expect(context, contains('favorite_color：绿色'));
    expect(context, contains('当前 active 用户事实优先于长期汇总'));
    expect(context, contains('用户喜欢橙色'));
    expect(context, isNot(contains('favorite_color：橙色')));
    expect((await storage.loadMemorySummary()).generatedText, '用户喜欢橙色');
  });

  test('only explicit history includes A with B as current', () async {
    await history();
    final result = await retriever.retrieve(
      currentMessage: '我以前最喜欢什么颜色？',
      now: now,
    );
    expect(result.selectedUserMemories.map((m) => m.id), ['b']);
    expect(result.selectedHistoricalUserMemories.map((m) => m.id), ['a']);
    expect(
      result.contextText,
      contains('过去：favorite_color：橙色；当前：favorite_color：绿色'),
    );
    expect((await storage.loadUserMemories()).first.sourceMessageIds, [
      'old-source',
    ]);
  });

  test('unrelated query does not inject a set of aliased facts', () async {
    await storage.saveUserMemories([
      fact('color', 'favorite_color', '绿色'),
      fact('food', 'favorite_food', '面条'),
      fact('drink', 'favorite_drink', '茶'),
      fact('game', 'game_preference', 'PVE'),
      fact('hobby', 'hobbies', '绘画'),
      fact('diet', 'dietary_restriction', '芹菜'),
    ]);
    for (final query in ['我今天想去哪里玩？', '这张图片是什么颜色？', '火箭怎样发射？']) {
      final result = await retriever.retrieve(currentMessage: query, now: now);
      expect(result.selectedUserMemories, isEmpty, reason: query);
    }
    final color = await retriever.retrieve(
      currentMessage: '我最喜欢什么颜色？',
      now: now,
    );
    expect(color.selectedUserMemories.map((m) => m.id), ['color']);
  });

  test(
    'unknown and generic keys get no alias and unrelated score stays zero',
    () async {
      for (final key in [
        'favorite_unknown',
        'not_favorite_color',
        '喜欢',
        '偏好',
      ]) {
        expect(UserMemoryKeyAliases.relevance(key, '我最喜欢什么颜色？'), 0);
      }
      await storage.saveUserMemories([fact('unknown', 'unknown', '绿色')]);
      expect(
        (await retriever.retrieve(
          currentMessage: '我喜欢什么颜色？',
          now: now,
        )).selectedUserMemories,
        isEmpty,
      );
    },
  );

  test(
    'existing current history limits and context budget still apply',
    () async {
      await storage.saveUserMemories([
        for (var i = 0; i < 8; i++)
          fact('active-$i', 'favorite_color', '绿色' * 200),
        for (var i = 0; i < 5; i++)
          UserMemory(
            id: 'old-$i',
            characterId: 'rc',
            key: 'favorite_color',
            value: '橙色' * 200,
            status: UserMemoryStatus.superseded,
            supersededById: 'active-0',
            createdAt: now,
          ),
      ]);
      await storage.saveMemorySummary(
        MemorySummary(characterId: 'rc', generatedText: '旧汇总' * 600),
      );
      final result = await retriever.retrieve(
        currentMessage: '我以前最喜欢什么颜色？',
        now: now,
      );
      expect(
        result.selectedUserMemories.length,
        Memory2Retriever.maximumUserMemories,
      );
      expect(
        result.selectedHistoricalUserMemories.length,
        inInclusiveRange(1, Memory2Retriever.maximumHistoricalUserMemories),
      );
      expect(
        result.contextText.length,
        lessThanOrEqualTo(Memory2Retriever.totalContextCharacters),
      );
      await storage.saveMemorySummary(const MemorySummary(characterId: 'rc'));
      final withoutSummary = await retriever.retrieve(
        currentMessage: '我以前最喜欢什么颜色？',
        now: now,
      );
      expect(
        withoutSummary.selectedHistoricalUserMemories.length,
        Memory2Retriever.maximumHistoricalUserMemories,
      );
    },
  );
}
