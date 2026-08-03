import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/chat_flow/chat_flow_engine.dart';
import 'package:peijianche_app/context_builder/context_build_result.dart';
import 'package:peijianche_app/context_builder/conversation_context.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/reply_strategy/reply_goal.dart';
import 'package:peijianche_app/reply_strategy/reply_strategy.dart';
import 'package:peijianche_app/reply_strategy/reply_strategy_engine.dart';
import 'package:peijianche_app/reply_strategy/response_shape.dart';

void main() {
  group('ReplyStrategyEngine', () {
    const flowEngine = ChatFlowEngine();
    const strategyEngine = ReplyStrategyEngine();

    ReplyStrategy strategyFor(String userText) {
      final conversation = ConversationContext([
        ChatMessage(role: 'user', content: userText),
      ]);
      return strategyEngine.plan(
        conversation: conversation,
        flow: flowEngine.plan(conversation),
      );
    }

    test('今天好累使用短安慰策略且不提问', () {
      final strategy = strategyFor('今天好累。');

      expect(strategy.goal, ReplyGoal.comfort);
      expect(strategy.tone, ReplyTone.gentle);
      expect(strategy.length, StrategyLength.short);
      expect(strategy.question, isFalse);
      expect(strategy.shape, ResponseShape.emotionalSupport);
    });

    test('哈哈你猜使用调侃策略', () {
      final strategy = strategyFor('哈哈你猜。');

      expect(strategy.goal, ReplyGoal.tease);
      expect(strategy.tone, ReplyTone.playful);
      expect(strategy.question, isFalse);
      expect(strategy.shape, ResponseShape.casualChat);
    });

    test('你知道为什么吗使用解释策略', () {
      final strategy = strategyFor('你知道为什么吗？');

      expect(strategy.goal, ReplyGoal.explain);
      expect(strategy.tone, ReplyTone.clear);
      expect(strategy.question, isFalse);
      expect(strategy.shape, ResponseShape.directExplanation);
    });

    test('策略只包含结构字段，不生成具体回复', () {
      final prompt = strategyFor('今天好累。').toPromptSection();

      expect(prompt, contains('goal=comfort'));
      expect(prompt, contains('tone=gentle'));
      expect(prompt, contains('length=short'));
      expect(prompt, contains('question=false'));
      expect(prompt, isNot(contains('辛苦啦')));
      expect(prompt, isNot(contains('抱抱')));
    });

    test('Reply Strategy 在 Chat Flow 之后加入模型请求', () {
      const base = ContextBuildResult(
        messages: [
          {'role': 'system', 'content': 'context builder\n\nchat flow'},
          {'role': 'user', 'content': '今天好累。'},
        ],
        systemPrompt: 'context builder\n\nchat flow',
      );
      final strategy = strategyFor('今天好累。');
      final result = strategyEngine.apply(context: base, strategy: strategy);

      expect(result.systemPrompt, startsWith('context builder\n\nchat flow'));
      expect(result.systemPrompt, contains('【Reply Strategy｜仅控制表达方向】'));
      expect(result.messages.last['content'], '今天好累。');
      expect(base.systemPrompt, isNot(contains('Reply Strategy')));
    });
  });
}
