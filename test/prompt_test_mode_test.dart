import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/context_builder/character_context.dart';
import 'package:peijianche_app/context_builder/conversation_context.dart';
import 'package:peijianche_app/context_builder/memory_context.dart';
import 'package:peijianche_app/context_builder/relationship_context.dart';
import 'package:peijianche_app/context_builder/response_strategy_context.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/prompt_test_mode.dart';
import 'package:peijianche_app/models/user_profile.dart';
import 'package:peijianche_app/services/context_builder.dart';
import 'package:peijianche_app/services/prompt_test_context_builder.dart';
import 'package:peijianche_app/services/prompt_test_snapshot_service.dart';

void main() {
  test(
    'pure persona test context keeps facts and memory without extra rules',
    () {
      final prompt = PromptTestContextBuilder.build(
        mode: PromptTestMode.personaOnly,
        memoryPrompt: '【已确认记忆】喜欢雨天',
        transientEventContext: '',
        profile: const CharacterProfile(
          characterId: 'test',
          age: '26',
          gender: '男',
          identity: '医生',
        ),
        settings: CharacterSettings.defaults(),
      );

      expect(prompt, contains('年龄：26'));
      expect(prompt, contains('身份：医生'));
      expect(prompt, contains('喜欢雨天'));
      expect(prompt, isNot(contains('极简聊天规则')));
      expect(prompt, isNot(contains('PersonalityStyle')));
    },
  );

  test('minimal mode adds exactly the dedicated six-rule block', () {
    final prompt = PromptTestContextBuilder.build(
      mode: PromptTestMode.minimalRules,
      memoryPrompt: '',
      transientEventContext: '',
      profile: const CharacterProfile(characterId: 'test'),
      settings: CharacterSettings.defaults(),
    );

    expect(prompt, contains('【极简聊天规则】'));
    for (var index = 1; index <= 6; index++) {
      expect(prompt, contains('$index.'));
    }
    expect(prompt, isNot(contains('7.')));
  });

  test('test-only ContextBuilder flags remove behavior enhancement only', () {
    final result = ContextBuilder.buildChatRequest(
      character: CharacterContext(
        settings: CharacterSettings.defaults(),
        userProfile: const UserProfile(peiCallName: '念念'),
        profile: const CharacterProfile(
          characterId: 'test',
          name: '测试角色',
          personalityDescription: '安静克制',
          speakingStyle: '简短直接',
        ),
      ),
      relationship: const RelationshipContext(relationshipState: '角色与用户关系：朋友'),
      memory: const MemoryContext(),
      conversation: ConversationContext([
        ChatMessage(role: 'user', content: '在吗'),
      ]),
      responseStrategy: const ResponseStrategyContext(
        dynamicPrompt: '【已确认记忆】喜欢雨天',
        mediaRules: '',
      ),
      messageContent: (message) => message.content,
      includeBehaviorRules: false,
      includeBaseRelationshipRules: false,
    );

    expect(result.systemPrompt, contains('角色本名：测试角色'));
    expect(result.systemPrompt, contains('安静克制'));
    expect(result.systemPrompt, contains('简短直接'));
    expect(result.systemPrompt, contains('喜欢雨天'));
    expect(result.systemPrompt, contains('角色与用户关系：朋友'));
    expect(result.systemPrompt, isNot(contains('【行为规则｜按任务加载】')));
    expect(result.systemPrompt, isNot(contains('林念念是裴简澈')));
    expect(result.messages.last['content'], '在吗');
  });

  test('snapshot displays messages in the real request order', () {
    PromptTestSnapshotService.capture(
      mode: PromptTestMode.minimalRules,
      messages: const [
        {'role': 'system', 'content': 'SYSTEM'},
        {'role': 'user', 'content': 'USER'},
        {'role': 'assistant', 'content': 'ASSISTANT'},
      ],
    );

    final snapshot = PromptTestSnapshotService.latest!;
    expect(snapshot.mode, PromptTestMode.minimalRules);
    expect(
      snapshot.displayText.indexOf('SYSTEM'),
      lessThan(snapshot.displayText.indexOf('USER')),
    );
    expect(
      snapshot.displayText.indexOf('USER'),
      lessThan(snapshot.displayText.indexOf('ASSISTANT')),
    );
  });
}
