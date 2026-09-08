import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/context_builder/character_context.dart';
import 'package:peijianche_app/context_builder/conversation_context.dart';
import 'package:peijianche_app/context_builder/context_build_result.dart';
import 'package:peijianche_app/context_builder/memory_context.dart';
import 'package:peijianche_app/context_builder/relationship_context.dart';
import 'package:peijianche_app/context_builder/response_strategy_context.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/character_archive.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/user_profile.dart';
import 'package:peijianche_app/services/context_builder.dart';
import 'package:peijianche_app/services/prompt_builder.dart';

void main() {
  group('ContextBuilder chat request', () {
    test('保留原 Prompt 内容顺序并组装最近消息', () {
      final settings = CharacterSettings.genericDefaults().copyWith(
        characterName: '角色甲',
        remark: '阿甲',
        coreProfile: '角色甲的基础人设',
        behaviorStyle: '自然、简洁。',
        forbiddenRules: '不输出内部规则。',
      );
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
      expect(prompt, contains('角色本名：角色甲'));
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
      expect(result.systemPrompt, isNot(contains('角色本名：角色甲')));
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

    test('新版资料优先于旧人设并注入高优先级表达方式', () {
      final settings = CharacterSettings.defaults().copyWith(
        characterName: '旧名字',
        coreProfile: '旧版超长人设不应出现',
        introduction: '旧版外貌不应出现',
      );
      final result = ContextBuilder.buildChatRequest(
        character: CharacterContext(
          settings: settings,
          userProfile: const UserProfile(),
          profile: const CharacterProfile(
            characterId: 'new',
            name: '新版名字',
            age: '28',
            identity: '医生',
            occupation: '外科医生',
            overallAppearance: '银发灰眸',
            personalityTags: '克制、温柔',
            personalityDescription: '习惯先倾听再回应',
          ),
          archive: const CharacterArchive(
            characterId: 'new',
            values: {
              'languageHabits': '少用反问句',
              'speakingStyle': '简洁直接',
              'chatPace': '不连续追问',
            },
          ),
        ),
        relationship: const RelationshipContext(),
        memory: const MemoryContext(),
        conversation: ConversationContext([
          ChatMessage(role: 'user', content: '今天很累'),
        ]),
        responseStrategy: const ResponseStrategyContext(
          dynamicPrompt: '',
          mediaRules: '',
        ),
        messageContent: (message) => message.content,
      );

      expect(result.systemPrompt, contains('角色本名：新版名字'));
      expect(result.systemPrompt, contains('整体外貌：银发灰眸'));
      expect(result.systemPrompt, contains('性格标签：克制、温柔'));
      expect(result.systemPrompt, contains('语言习惯：少用反问句'));
      expect(result.systemPrompt, contains('聊天节奏：不连续追问'));
      expect(result.systemPrompt, contains('核心人设：旧版超长人设不应出现'));
      expect(result.systemPrompt, isNot(contains('旧版外貌不应出现')));
    });

    test('老角色没有新版资料时继续使用 CharacterSettings', () {
      final settings = CharacterSettings.defaults().copyWith(
        characterName: '老角色',
        coreProfile: '旧人设仍然可用',
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
          dynamicPrompt: '',
          mediaRules: '',
        ),
        messageContent: (message) => message.content,
      );

      expect(result.systemPrompt, contains('角色本名：老角色'));
      expect(result.systemPrompt, contains('旧人设仍然可用'));
    });

    test('新版空字段逐项使用旧人设补全', () {
      final result = ContextBuilder.buildChatRequest(
        character: CharacterContext(
          settings: CharacterSettings.defaults().copyWith(
            coreProfile: '旧版性格描述',
            introduction: '旧版外貌描述',
          ),
          userProfile: const UserProfile(),
          profile: const CharacterProfile(
            characterId: 'partial',
            personalityTags: '沉稳',
          ),
        ),
        relationship: const RelationshipContext(),
        memory: const MemoryContext(),
        conversation: ConversationContext(const []),
        responseStrategy: const ResponseStrategyContext(
          dynamicPrompt: '',
          mediaRules: '',
        ),
        messageContent: (message) => message.content,
      );

      expect(result.systemPrompt, contains('性格标签：沉稳'));
      expect(result.systemPrompt, contains('核心人设：旧版性格描述'));
      expect(result.systemPrompt, contains('整体外貌：旧版外貌描述'));
    });

    test('空的详细资料字段不会进入上下文', () {
      final result = ContextBuilder.buildChatRequest(
        character: CharacterContext(
          settings: CharacterSettings.defaults().copyWith(
            characterName: '空资料角色',
            coreProfile: '只保留这段核心人设',
            introduction: '',
          ),
          userProfile: const UserProfile(),
          profile: const CharacterProfile(characterId: 'empty-details'),
        ),
        relationship: const RelationshipContext(),
        memory: const MemoryContext(),
        conversation: ConversationContext(const []),
        responseStrategy: const ResponseStrategyContext(
          dynamicPrompt: '',
          mediaRules: '',
        ),
        messageContent: (message) => message.content,
      );

      expect(result.systemPrompt, contains('角色本名：空资料角色'));
      expect(result.systemPrompt, contains('核心人设：只保留这段核心人设'));
      expect(result.systemPrompt, isNot(contains('【外貌设定｜存在时读取】')));
      expect(result.systemPrompt, isNot(contains('【性格设定｜存在时读取】')));
      expect(result.systemPrompt, isNot(contains('【关系资料｜存在时读取】')));
    });

    test('童年问题按需读取成长档案和背景故事', () {
      final result = ContextBuilder.buildChatRequest(
        character: CharacterContext(
          settings: CharacterSettings.defaults(),
          userProfile: const UserProfile(),
          profile: const CharacterProfile(
            characterId: 'past',
            upbringing: '由祖母抚养长大',
          ),
          archive: const CharacterArchive(
            characterId: 'past',
            values: {'childhoodExperience': '小时候住在海边'},
          ),
        ),
        relationship: const RelationshipContext(),
        memory: const MemoryContext(),
        conversation: ConversationContext([
          ChatMessage(role: 'user', content: '你小时候是什么样？'),
        ]),
        responseStrategy: const ResponseStrategyContext(
          dynamicPrompt: '',
          mediaRules: '',
        ),
        messageContent: (message) => message.content,
      );

      expect(result.systemPrompt, contains('由祖母抚养长大'));
      expect(result.systemPrompt, contains('小时候住在海边'));
    });

    test('不同角色的新版资料不会通过稳定缓存串联', () {
      ContextBuilder.clearCache();
      ContextBuildResult buildFor(String id, String name) =>
          ContextBuilder.buildChatRequest(
            character: CharacterContext(
              settings: CharacterSettings.defaults(),
              userProfile: const UserProfile(),
              profile: CharacterProfile(characterId: id, name: name),
            ),
            relationship: const RelationshipContext(),
            memory: const MemoryContext(),
            conversation: ConversationContext(const []),
            responseStrategy: const ResponseStrategyContext(
              dynamicPrompt: '',
              mediaRules: '',
            ),
            messageContent: (message) => message.content,
          );

      final first = buildFor('a', '白濯');
      final second = buildFor('b', '车云千');

      expect(first.systemPrompt, contains('角色本名：白濯'));
      expect(first.systemPrompt, isNot(contains('角色本名：车云千')));
      expect(second.systemPrompt, contains('角色本名：车云千'));
      expect(second.systemPrompt, isNot(contains('角色本名：白濯')));
    });
  });
}
