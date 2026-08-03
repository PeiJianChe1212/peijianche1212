import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/chat_flow/chat_flow_engine.dart';
import 'package:peijianche_app/chat_flow/reply_intent.dart';
import 'package:peijianche_app/context_builder/context_build_result.dart';
import 'package:peijianche_app/context_builder/conversation_context.dart';
import 'package:peijianche_app/models/chat_message.dart';

void main() {
  group('ChatFlowEngine', () {
    const engine = ChatFlowEngine();

    test('回答上一轮问题后不立即继续提问', () {
      final conversation = ConversationContext([
        ChatMessage(role: 'assistant', content: '你是先吃饭还是先玩手机？'),
        ChatMessage(role: 'user', content: '摸手机和你说早安。'),
      ]);

      final plan = engine.plan(conversation);

      expect(plan.intent, ReplyIntent.response);
      expect(plan.questionDesire, lessThan(0.1));
      expect(plan.shouldAvoidQuestion, isTrue);
      expect(plan.forbidChoiceQuestion, isTrue);
      expect(plan.toPromptSection(), contains('不要紧接着抛出新问题'));
    });

    test('用户说今天好累时优先安慰陪伴', () {
      final plan = engine.plan(
        ConversationContext([ChatMessage(role: 'user', content: '今天好累。')]),
      );

      expect(plan.intent, ReplyIntent.care);
      expect(plan.shouldAvoidQuestion, isTrue);
      expect(plan.toPromptSection(), contains('先接住用户的话'));
    });

    test('最近出现选择题时禁止继续生成选择题', () {
      final plan = engine.plan(
        ConversationContext([
          ChatMessage(role: 'assistant', content: '你想吃饭还是继续躺着？'),
          ChatMessage(role: 'user', content: '继续躺着。'),
        ]),
      );

      expect(plan.forbidChoiceQuestion, isTrue);
      expect(plan.questionDesire, 0);
      expect(plan.toPromptSection(), contains('本轮禁止生成'));
    });

    test('没有问号的中文问句和选择题也能识别', () {
      final plan = engine.plan(
        ConversationContext([
          ChatMessage(role: 'assistant', content: '你现在起来了吗'),
          ChatMessage(role: 'user', content: '还没有'),
        ]),
      );
      final choicePlan = engine.plan(
        ConversationContext([
          ChatMessage(role: 'assistant', content: '吃饭还是继续玩手机'),
          ChatMessage(role: 'user', content: '玩手机'),
        ]),
      );

      expect(plan.previousAssistantAskedQuestion, isTrue);
      expect(plan.questionDesire, lessThan(0.1));
      expect(choicePlan.forbidChoiceQuestion, isTrue);
    });

    test('简短收尾允许自然结束', () {
      final plan = engine.plan(
        ConversationContext([ChatMessage(role: 'user', content: '知道了。')]),
      );

      expect(plan.intent, ReplyIntent.endNaturally);
      expect(plan.toPromptSection(), contains('允许只回复自然短句'));
    });

    test('连续 20 轮不会每轮都安排提问', () {
      final messages = <ChatMessage>[];
      var questionTurns = 0;
      for (var turn = 0; turn < 20; turn++) {
        messages.add(ChatMessage(role: 'user', content: '第 $turn 轮日常聊天'));
        final plan = engine.plan(ConversationContext(messages));
        if (plan.intent == ReplyIntent.askQuestion) questionTurns++;
        messages.add(
          ChatMessage(
            role: 'assistant',
            content: plan.intent == ReplyIntent.askQuestion
                ? '偶尔问一句可以吗？'
                : '自然接话，不强制提问。',
          ),
        );
      }

      expect(questionTurns, lessThanOrEqualTo(3));
    });

    test('策略在 Context Builder 之后加入模型请求', () {
      const base = ContextBuildResult(
        messages: [
          {'role': 'system', 'content': 'character context'},
          {'role': 'user', 'content': '你好'},
        ],
        systemPrompt: 'character context',
      );
      final plan = engine.plan(
        ConversationContext([ChatMessage(role: 'user', content: '你好')]),
      );
      final result = engine.apply(context: base, plan: plan);

      expect(result.systemPrompt, startsWith('character context'));
      expect(result.systemPrompt, contains('【Chat Flow｜本轮回复节奏】'));
      expect(result.messages.last['content'], '你好');
      expect(base.systemPrompt, isNot(contains('Chat Flow')));
    });
  });
}
