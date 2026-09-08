import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/chat_flow/chat_flow_engine.dart';
import 'package:peijianche_app/context_builder/context_build_result.dart';
import 'package:peijianche_app/context_builder/conversation_context.dart';
import 'package:peijianche_app/models/chat_message.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/personality_style/personality_style.dart';
import 'package:peijianche_app/personality_style/personality_style_engine.dart';
import 'package:peijianche_app/reply_strategy/reply_goal.dart';
import 'package:peijianche_app/reply_strategy/reply_strategy_engine.dart';

void main() {
  group('PersonalityStyleEngine', () {
    const engine = PersonalityStyleEngine();
    final conversation = ConversationContext([
      ChatMessage(role: 'user', content: '今天好累。'),
    ]);
    final flow = const ChatFlowEngine().plan(conversation);
    final replyStrategy = const ReplyStrategyEngine().plan(
      conversation: conversation,
      flow: flow,
    );

    final peiJianChe = CharacterSettings.genericDefaults().copyWith(
      characterName: '冷感测试角色',
      remark: '测试',
      introduction: '看起来冷淡疏离，实际外冷内热。',
      coreProfile: '外冷内热，嘴硬爱调侃，会一本正经地接梗。',
      behaviorStyle: '偶尔故意逗人，幽默接梗。',
      exampleDialogues: '',
      tsundere: 0.75,
    );
    final baiZhuo = CharacterSettings.defaults().copyWith(
      characterName: '白濯',
      remark: '白濯',
      introduction: '温暖热情，活泼爱笑。',
      coreProfile: '白濯性格温暖、热心，习惯直接表达关心。',
      behaviorStyle: '说话自然、直率、健谈，会直接表达情绪。',
      exampleDialogues: '',
      replyLength: 'long',
      initiative: 0.82,
      intimacy: 0.82,
      tsundere: 0.12,
    );
    final xuanMo = CharacterSettings.defaults().copyWith(
      characterName: '玄墨',
      remark: '玄墨',
      introduction: '沉稳强势，克制寡言。',
      coreProfile: '玄墨习惯保持主导，情绪克制，不动声色。',
      behaviorStyle: '表达正式严谨、言简意赅，很少主动展开。',
      exampleDialogues: '',
      replyLength: 'short',
      initiative: 0.2,
      intimacy: 0.25,
      tsundere: 0.1,
    );

    test('相同 comfort 目标下三个角色 Style Context 不同', () {
      expect(replyStrategy.goal, ReplyGoal.comfort);

      final peiStyle = engine.resolve(
        settings: peiJianChe,
        replyStrategy: replyStrategy,
      );
      final baiStyle = engine.resolve(
        settings: baiZhuo,
        replyStrategy: replyStrategy,
      );
      final xuanStyle = engine.resolve(
        settings: xuanMo,
        replyStrategy: replyStrategy,
      );

      expect(peiStyle.toPromptSection(), isNot(baiStyle.toPromptSection()));
      expect(baiStyle.toPromptSection(), isNot(xuanStyle.toPromptSection()));
      expect(xuanStyle.toPromptSection(), isNot(peiStyle.toPromptSection()));
    });

    test('外冷内热角色从已有资料解析冷感与调侃表达', () {
      final style = engine.resolve(
        settings: peiJianChe,
        replyStrategy: replyStrategy,
      );

      expect(style.tone, StyleTone.coldButCaring);
      expect(style.emotionExpression, EmotionExpression.teasing);
      expect(style.humorLevel, HumorLevel.high);
    });

    test('白濯与玄墨分别读取各自资料而非角色名字映射', () {
      final baiStyle = engine.resolve(
        settings: baiZhuo,
        replyStrategy: replyStrategy,
      );
      final xuanStyle = engine.resolve(
        settings: xuanMo,
        replyStrategy: replyStrategy,
      );

      expect(baiStyle.tone, StyleTone.playful);
      expect(baiStyle.emotionExpression, EmotionExpression.direct);
      expect(baiStyle.initiative, StyleInitiative.high);
      expect(baiStyle.length, StyleLength.long);

      expect(xuanStyle.tone, StyleTone.dominant);
      expect(xuanStyle.emotionExpression, EmotionExpression.reserved);
      expect(xuanStyle.initiative, StyleInitiative.low);
      expect(xuanStyle.length, StyleLength.short);
    });

    test('只追加风格字段且位于 Reply Strategy 之后', () {
      const base = ContextBuildResult(
        messages: [
          {
            'role': 'system',
            'content': 'context\n\nchat flow\n\nreply strategy',
          },
          {'role': 'user', 'content': '今天好累。'},
        ],
        systemPrompt: 'context\n\nchat flow\n\nreply strategy',
      );
      final style = engine.resolve(
        settings: peiJianChe,
        replyStrategy: replyStrategy,
      );
      final result = engine.apply(context: base, style: style);

      expect(
        result.systemPrompt,
        startsWith('context\n\nchat flow\n\nreply strategy'),
      );
      expect(result.systemPrompt, contains('tone=cold_but_caring'));
      expect(result.systemPrompt, contains('emotion=teasing'));
      expect(result.systemPrompt, isNot(contains('别熬夜')));
      expect(base.systemPrompt, isNot(contains('Personality Style')));
    });
  });
}
