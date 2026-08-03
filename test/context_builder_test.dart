import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/context_builder/character_context.dart';
import 'package:peijianche_app/context_builder/conversation_context.dart';
import 'package:peijianche_app/context_builder/memory_context.dart';
import 'package:peijianche_app/context_builder/relationship_context.dart';
import 'package:peijianche_app/context_builder/response_strategy_context.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/user_profile.dart';
import 'package:peijianche_app/services/context_builder.dart';
import 'package:peijianche_app/services/prompt_builder.dart';

void main() {
  group('ContextBuilder chat request', () {
    test('保留原 Prompt 内容顺序并组装最近消息', () {
      final settings = CharacterSettings.defaults();
      const userProfile = UserProfile();
      const memory = MemoryContext(confirmedMemory: '【已确认记忆】\n- 喜欢雨天');
      final dynamicPrompt = PromptBuilder.buildDynamicSystemPrompt(
        timeContext: 'time',
        conversationEnginePrompt: 'conversation rules',
        personalityPrompt: 'personality',
        replyLengthPrompt: 'length',
        memoryPrompt: memory.confirmedMemory,
        activityPrompt: 'activity',
      );
      final conversation = ConversationContext([
        ChatMessage(role: 'user', content: '你好'),
      ]);

      final result = ContextBuilder.buildChatRequest(
        character: CharacterContext(
          settings: settings,
          userProfile: userProfile,
          styleExamples: PromptBuilder.buildStyleExamplesPrompt(settings),
        ),
        relationship: const RelationshipContext(
          echoContext: 'echo',
          sharedWorldContext: 'world',
          relationshipState: 'relationship',
          socialProtocol: 'social',
        ),
        memory: memory,
        conversation: conversation,
        responseStrategy: ResponseStrategyContext(
          dynamicPrompt: dynamicPrompt,
          mediaRules: 'media',
        ),
        messageContent: (message) => message.content,
      );

      final prompt = result.systemPrompt;
      expect(prompt, contains('角色本名：裴简澈'));
      expect(prompt.indexOf(dynamicPrompt), lessThan(prompt.indexOf('echo')));
      expect(prompt.indexOf('echo'), lessThan(prompt.indexOf('world')));
      expect(
        prompt.indexOf('relationship'),
        lessThan(prompt.indexOf('social')),
      );
      expect(prompt.indexOf('social'), lessThan(prompt.indexOf('media')));
      expect(result.messages, hasLength(2));
      expect(result.messages.last['content'], '你好');
    });

    test('角色上下文不绑定单一角色', () {
      final settings = CharacterSettings.defaults().copyWith(
        characterName: '车云千',
        remark: '云千',
        coreProfile: '车云千的固定人物设定',
      );
      final result = ContextBuilder.buildChatRequest(
        character: CharacterContext(
          settings: settings,
          userProfile: const UserProfile(),
        ),
        relationship: const RelationshipContext(),
        memory: const MemoryContext(),
        conversation: ConversationContext(const []),
        responseStrategy: const ResponseStrategyContext(
          dynamicPrompt: 'dynamic',
          mediaRules: 'media',
        ),
        messageContent: (message) => message.content,
      );

      expect(result.systemPrompt, contains('角色本名：车云千'));
      expect(result.systemPrompt, contains('车云千的固定人物设定'));
      expect(result.systemPrompt, isNot(contains('角色本名：裴简澈')));
    });

    test('Conversation Context 只发送最近 36 条有效消息', () {
      final messages = List<ChatMessage>.generate(
        40,
        (index) => ChatMessage(role: 'user', content: '$index'),
      )..add(ChatMessage(role: 'system', content: 'ignored'));
      final context = ConversationContext(messages);

      expect(context.messages, hasLength(40));
      expect(context.recentMessages, hasLength(36));
      expect(context.recentMessages.first.content, '4');
    });
  });
}
