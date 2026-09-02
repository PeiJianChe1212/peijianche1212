import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/config/peilink_runtime.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/pending_memory.dart';
import 'package:peijianche_app/models/user_profile.dart';
import 'package:peijianche_app/pages/memory_page.dart';
import 'package:peijianche_app/pages/memory_review_page.dart';
import 'package:peijianche_app/services/character_registry_service.dart';
import 'package:peijianche_app/services/character_settings_storage_service.dart';
import 'package:peijianche_app/services/deepseek_service.dart';
import 'package:peijianche_app/services/memory_review_service.dart';
import 'package:peijianche_app/services/memory_storage_service.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';
import 'package:peijianche_app/services/user_profile_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  AiCharacter character(String id, String name) => AiCharacter(
    id: id,
    characterName: name,
    remark: '',
    createdAt: DateTime(2026, 8, 22),
  );

  setUp(() async {
    PeiLinkRuntime.configure(PeiLinkBuild.unspecified);
    documents = await Directory.systemTemp.createTemp('memory_scope_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => documents.path);
    await CharacterRegistryService().saveAllCharacters([
      character('character-a', '角色甲'),
      character('character-b', '角色乙'),
    ]);
    await CharacterSettingsStorageService(
      characterId: 'character-a',
    ).saveSettings(
      CharacterSettings.defaults().copyWith(
        characterName: '设置甲',
        coreProfile: '甲的独立设定',
      ),
    );
    await CharacterSettingsStorageService(
      characterId: 'character-b',
    ).saveSettings(
      CharacterSettings.defaults().copyWith(
        characterName: '设置乙',
        coreProfile: '乙的独立设定',
      ),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  test('Memory 页面与待审核页保留显式角色绑定', () {
    const memory = MemoryPage(characterId: 'character-b');
    const review = MemoryReviewPage(characterId: 'character-b');
    expect(memory.characterId, 'character-b');
    expect(review.characterId, 'character-b');
  });

  test('角色 B 提取输入使用 B 名称、B Settings 与动态用户昵称', () async {
    await UserProfileStorageService().saveProfile(
      const UserProfile(nickname: '小满'),
    );
    final service = DeepSeekService();
    addTearDown(service.dispose);
    final scope = await service.buildMemoryExtractionScope(
      characterId: 'character-b',
      messages: [
        ChatMessage(role: 'user', content: '我喜欢爵士乐'),
        ChatMessage(role: 'assistant', content: '我记住了'),
      ],
    );

    expect(scope.characterId, 'character-b');
    expect(scope.character.characterName, '角色乙');
    expect(scope.characterSettings.coreProfile, '乙的独立设定');
    expect(scope.transcript, contains('小满：我喜欢爵士乐'));
    expect(scope.transcript, contains('角色乙：我记住了'));
    expect(scope.transcript, isNot(contains('角色甲')));
    expect(scope.transcript, isNot(contains('裴简澈')));
    expect(scope.transcript, isNot(contains('林念念')));
  });

  test('用户昵称为空时使用中性称呼用户', () async {
    await UserProfileStorageService().saveProfile(
      const UserProfile(nickname: ''),
    );
    final service = DeepSeekService();
    addTearDown(service.dispose);
    final scope = await service.buildMemoryExtractionScope(
      characterId: 'character-b',
      messages: [ChatMessage(role: 'user', content: '记住这件事')],
    );

    expect(scope.userName, '用户');
    expect(scope.transcript, '用户：记住这件事');
    expect(scope.transcript, isNot(contains('林念念')));
  });

  test('B 的提取结果只保存到 B Memory，A 不受影响', () async {
    final candidate = PendingMemory(
      content: '用户长期喜欢爵士乐',
      reason: '稳定偏好',
      category: '兴趣偏好',
    );
    final review = MemoryReviewService(characterId: 'character-b');
    await review.addCandidates([candidate]);
    await review.approve(candidate);

    final memoryA = await MemoryStorageService(
      characterId: 'character-a',
    ).loadItems();
    final memoryB = await Memory2StorageService(
      characterId: 'character-b',
    ).loadUserMemories();
    expect(memoryA, isEmpty);
    expect(memoryB.map((item) => item.value), ['用户长期喜欢爵士乐']);
    expect(
      await MemoryStorageService(characterId: 'character-b').loadItems(),
      isEmpty,
    );
  });

  test('单角色显式作用域流程保持正常', () async {
    await CharacterRegistryService().saveAllCharacters([
      character('only-character', '唯一角色'),
    ]);
    await CharacterSettingsStorageService(
      characterId: 'only-character',
    ).saveSettings(
      CharacterSettings.defaults().copyWith(
        characterName: '唯一角色设置',
        coreProfile: '单角色独立设定',
      ),
    );
    final service = DeepSeekService();
    addTearDown(service.dispose);
    final scope = await service.buildMemoryExtractionScope(
      characterId: 'only-character',
      messages: [ChatMessage(role: 'assistant', content: '你好')],
    );
    expect(scope.transcript, '唯一角色：你好');
    expect(scope.characterSettings.coreProfile, '单角色独立设定');
  });
}
