import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/character_user_profile.dart';
import 'package:peijianche_app/models/memory_summary.dart';
import 'package:peijianche_app/models/user_memory.dart';
import 'package:peijianche_app/services/event_memory_lifecycle_service.dart';
import 'package:peijianche_app/services/memory2_chat_context_builder.dart';
import 'package:peijianche_app/services/memory2_retriever.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';

void main() {
  late Directory root;
  late Memory2StorageService storage;
  late Memory2Retriever retriever;
  final now = DateTime.utc(2026, 9, 4);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('memory201_summary_priority_');
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
  Future<void> seed(String summary) async {
    await storage.saveUserMemories([
      UserMemory(
        id: 'a',
        characterId: 'rc',
        key: 'favorite_color',
        value: '橙色',
        status: UserMemoryStatus.superseded,
        supersededById: 'b',
        createdAt: now,
      ),
      UserMemory(
        id: 'b',
        characterId: 'rc',
        key: 'favorite_color',
        value: '绿色',
        mergedFromIds: ['a'],
        userConfirmed: true,
        createdAt: now,
      ),
    ]);
    await storage.saveMemorySummary(
      MemorySummary(characterId: 'rc', generatedText: summary),
    );
  }

  Future<String> context(String query) async => Memory2ChatContextBuilder.build(
    retrieval: await retriever.retrieve(currentMessage: query, now: now),
    characterUserProfile: const CharacterUserProfile(characterId: 'rc'),
  );
  const title = '【当前用户事实｜active，优先于 Summary 中的旧值】';
  test(
    'current conflict has selected active authority after unchanged Summary',
    () async {
      await seed('用户喜欢橙色');
      final text = await context('我现在最喜欢什么颜色？');
      expect(text, contains('Summary 是长期概括，可能滞后'));
      expect(text, contains('不得采用冲突的 Summary 旧值'));
      expect(text, contains('$title\n- 当前：favorite_color：绿色'));
      expect(text.indexOf(title), greaterThan(text.indexOf('用户喜欢橙色')));
      expect(text.substring(text.indexOf(title)), isNot(contains('橙色')));
      expect((await storage.loadUserMemories()).length, 2);
    },
  );
  test('nonconflicting Summary sentences remain byte for byte', () async {
    const summary = '用户喜欢橙色。\n用户习惯晚上听音乐。';
    await seed(summary);
    expect(await context('我现在最喜欢什么颜色？'), contains(summary));
    expect((await storage.loadMemorySummary()).generatedText, summary);
  });
  test('correct past and present description is not deleted', () async {
    const summary = '用户以前喜欢橙色，现在喜欢绿色。';
    await seed(summary);
    expect(await context('我现在最喜欢什么颜色？'), contains(summary));
  });
  test(
    'multiple selected active facts remain authoritative independently',
    () async {
      await seed('用户喜欢橙色。用户晚上听音乐。');
      await storage.upsertUserMemory(
        UserMemory(
          id: 'drink',
          characterId: 'rc',
          key: 'favorite_drink',
          value: '茶',
          createdAt: now,
        ),
      );
      final text = await context('我喜欢什么颜色，喜欢喝什么？');
      final current = text.substring(text.indexOf(title));
      expect(current, contains('当前：favorite_color：绿色'));
      expect(current, contains('当前：favorite_drink：茶'));
      expect(text, contains('用户晚上听音乐'));
    },
  );
  test('without selected active facts Summary is still usable', () async {
    await seed('用户习惯晚上听音乐。');
    final text = await context('晚上听什么音乐？');
    expect(text, contains('用户习惯晚上听音乐。'));
    expect(text, isNot(contains(title)));
  });
  test(
    'historical recall retains A and current B distinct from Summary',
    () async {
      await seed('用户喜欢橙色。');
      final result = await retriever.retrieve(
        currentMessage: '我以前最喜欢什么颜色？',
        now: now,
      );
      expect(result.selectedHistoricalUserMemories.map((m) => m.id), ['a']);
      expect(result.selectedUserMemories.map((m) => m.id), ['b']);
      final text = Memory2ChatContextBuilder.build(
        retrieval: result,
        characterUserProfile: const CharacterUserProfile(characterId: 'rc'),
      );
      expect(text, contains('过去：favorite_color：橙色；当前：favorite_color：绿色'));
      expect(text.substring(text.indexOf(title)), isNot(contains('橙色')));
    },
  );
  test(
    'authority echo remains bounded to the existing selected item limits',
    () async {
      await storage.saveUserMemories([
        for (var i = 0; i < 8; i++)
          UserMemory(
            id: '$i',
            characterId: 'rc',
            key: 'favorite_color',
            value: '绿色' * 300,
            createdAt: now,
          ),
      ]);
      final text = await context('我喜欢什么颜色？');
      final block = text.substring(text.indexOf(title));
      expect('- 当前：'.allMatches(block).length, 4);
      expect(
        block.length,
        lessThanOrEqualTo(
          title.length + 1 + 4 * (Memory2Retriever.userItemCharacters + 7),
        ),
      );
    },
  );
}
