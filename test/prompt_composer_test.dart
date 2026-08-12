import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/chat_flow/chat_flow_engine.dart';
import 'package:peijianche_app/chat_flow/reply_intent.dart';
import 'package:peijianche_app/context_builder/context_build_result.dart';
import 'package:peijianche_app/context_builder/conversation_context.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/prompt_composer/prompt_composer.dart';
import 'package:peijianche_app/prompt_composer/prompt_context.dart';
import 'package:peijianche_app/reply_strategy/reply_goal.dart';
import 'package:peijianche_app/reply_strategy/reply_strategy.dart';
import 'package:peijianche_app/reply_strategy/reply_strategy_engine.dart';

void main() {
  group('PromptComposer', () {
    ContextBuildResult base(String character, String userText) =>
        ContextBuildResult(
          messages: [
            {'role': 'system', 'content': '角色背景：$character'},
            {'role': 'user', 'content': userText},
          ],
          systemPrompt: '角色背景：$character',
        );

    test('普通聊天保留角色上下文和最近消息', () {
      final result = PromptComposer(baseContext: base('裴简澈', '早安。'))
          .addContext(PromptContext.chatFlow('flow=response'))
          .addContext(PromptContext.replyStrategy('goal=acknowledge'))
          .compose();

      expect(result.systemPrompt, startsWith('角色背景：裴简澈'));
      expect(result.systemPrompt, contains('flow=response'));
      expect(result.systemPrompt, contains('goal=acknowledge'));
      expect(result.messages.last['content'], '早安。');
    });

    test('情绪聊天保持 care、comfort 和禁止强制提问', () {
      final conversation = ConversationContext([
        ChatMessage(role: 'user', content: '今天好累。'),
      ]);
      final flow = const ChatFlowEngine().plan(conversation);
      final strategy = const ReplyStrategyEngine().plan(
        conversation: conversation,
        flow: flow,
      );
      final result = PromptComposer(baseContext: base('裴简澈', '今天好累。'))
          .addContext(PromptContext.chatFlow(flow.toPromptSection()))
          .addContext(PromptContext.replyStrategy(strategy.toPromptSection()))
          .compose();

      expect(flow.intent, ReplyIntent.care);
      expect(strategy.goal, ReplyGoal.comfort);
      expect(strategy.length, StrategyLength.medium);
      expect(strategy.question, isFalse);
      expect(result.systemPrompt, contains('goal=comfort'));
      expect(result.systemPrompt, contains('question=false'));
      expect(result.systemPrompt, contains('普通聊天默认组织成 2 到 5 句'));
      expect(
        result.systemPrompt.indexOf('普通聊天默认组织成 2 到 5 句'),
        greaterThan(result.systemPrompt.indexOf('【Chat Flow｜本轮回复节奏】')),
      );
    });

    test('按明确优先级编排，当前回复策略最高', () {
      final result = PromptComposer(baseContext: base('角色', '消息'))
          .addContext(
            const PromptContext(
              id: 'relationship',
              type: PromptContextType.relationship,
              content: 'RELATIONSHIP',
              priority: PromptContextPriority.relationship,
            ),
          )
          .addContext(
            const PromptContext(
              id: 'memory',
              type: PromptContextType.memory,
              content: 'MEMORY',
              priority: PromptContextPriority.memory,
            ),
          )
          .addContext(PromptContext.replyStrategy('REPLY_STRATEGY'))
          .addContext(
            const PromptContext(
              id: 'conversation',
              type: PromptContextType.conversation,
              content: 'CONVERSATION',
              priority: PromptContextPriority.conversation,
            ),
          )
          .addContext(PromptContext.personalityStyle('PERSONALITY_STYLE'))
          .compose();
      final prompt = result.systemPrompt;

      expect(
        prompt.indexOf('MEMORY'),
        lessThan(prompt.indexOf('CONVERSATION')),
      );
      expect(
        prompt.indexOf('CONVERSATION'),
        lessThan(prompt.indexOf('RELATIONSHIP')),
      );
      expect(
        prompt.indexOf('RELATIONSHIP'),
        lessThan(prompt.indexOf('PERSONALITY_STYLE')),
      );
      expect(
        prompt.indexOf('PERSONALITY_STYLE'),
        lessThan(prompt.indexOf('REPLY_STRATEGY')),
      );
    });

    test('裴简澈和车云千请求相互隔离', () {
      final pei = PromptComposer(
        baseContext: base('裴简澈', '早安。'),
      ).addContext(PromptContext.replyStrategy('goal=acknowledge')).compose();
      final che = PromptComposer(
        baseContext: base('车云千', '早安。'),
      ).addContext(PromptContext.replyStrategy('goal=acknowledge')).compose();

      expect(pei.systemPrompt, contains('裴简澈'));
      expect(pei.systemPrompt, isNot(contains('车云千')));
      expect(che.systemPrompt, contains('车云千'));
      expect(che.systemPrompt, isNot(contains('裴简澈')));
    });

    test('未来扩展 Context 可插拔且同 id 不会重复', () {
      final composer = PromptComposer(baseContext: base('角色', '消息'))
        ..addContext(
          PromptContext.extension(id: 'echo', content: 'old echo context'),
        )
        ..addContext(
          PromptContext.extension(id: 'echo', content: 'new echo context'),
        )
        ..addContext(
          PromptContext.extension(
            id: 'life_event',
            content: 'life event context',
          ),
        );
      final result = composer.compose();

      expect(result.systemPrompt, isNot(contains('old echo context')));
      expect(result.systemPrompt, contains('new echo context'));
      expect(result.systemPrompt, contains('life event context'));
    });
  });
}
