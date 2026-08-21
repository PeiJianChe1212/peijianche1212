import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/character_profile.dart';
import 'package:peijianche_app/models/character_settings.dart';
import 'package:peijianche_app/models/life_moment.dart';
import 'package:peijianche_app/services/context_builder.dart';
import 'package:peijianche_app/services/echo_expression_prompt.dart';
import 'package:peijianche_app/services/moment_engine_service.dart';

void main() {
  test('Echo rules allow natural length, questions, and ordinary posts', () {
    final rules = EchoExpressionPrompt.rules();
    expect(rules, contains('内容需要多少就写多少'));
    expect(rules, contains('可以自然使用问句'));
    expect(rules, contains('普通、琐碎'));
    expect(rules, isNot(contains('20 至 180')));
    expect(rules, isNot(contains('一到三小段')));
    expect(rules, isNot(contains('不要提问')));
    expect(rules, isNot(contains('聚焦具体细节和余味')));
  });

  test('Echo expression profile includes voice but excludes full archives', () {
    final profile = EchoExpressionPrompt.expressionProfile(
      profile: const CharacterProfile(
        characterId: 'role',
        name: '临川',
        identity: '普通居民',
        occupation: '设计师',
        personalityDescription: '不爱铺垫，观察细致',
        personalityTags: '冷淡、幽默',
        speakingStyle: '短句，偶尔吐槽',
        overallAppearance: '银白短发，身形修长',
        backgroundStory: '完整背景故事不应进入',
        worldview: '完整世界观不应进入',
        possessions: '完整物品清单不应进入',
      ),
    );
    expect(profile, contains('性格描述：不爱铺垫，观察细致'));
    expect(profile, contains('说话风格：短句，偶尔吐槽'));
    expect(profile, contains('职业或生活身份：设计师'));
    expect(profile, isNot(contains('银白短发')));
    expect(profile, isNot(contains('完整背景故事')));
    expect(profile, isNot(contains('完整世界观')));
    expect(profile, isNot(contains('完整物品清单')));
  });

  test('Echo prompt order keeps voice before rules and facts last', () {
    final prompt = ContextBuilder.build(
      task: ContextTask.echo,
      settings: CharacterSettings.defaults(),
      expressionProfile: '表达资料',
      taskRules: '正文规则',
      relationshipContext: '关系事实',
      socialProtocol: '多角色边界',
      sourceFacts: '生活事实',
      includeBehaviorRules: false,
    );
    expect(prompt.indexOf('表达资料'), lessThan(prompt.indexOf('正文规则')));
    expect(prompt.indexOf('正文规则'), lessThan(prompt.indexOf('关系事实')));
    expect(prompt.indexOf('关系事实'), lessThan(prompt.indexOf('多角色边界')));
    expect(prompt.indexOf('多角色边界'), lessThan(prompt.indexOf('生活事实')));
  });

  test('Moment prompt treats details and story shape as optional', () {
    final service = MomentEngineService(
      character: AiCharacter(
        id: 'role',
        characterName: '角色',
        remark: '',
        createdAt: DateTime.utc(2026, 8, 21),
      ),
    );
    final prompt = service.buildPrompt(
      settings: CharacterSettings.defaults(),
      candidates: [
        LifeMomentCandidate(
          id: 'moment',
          scene: '家里',
          event: '吃了西瓜',
          detail: '很甜',
          feeling: '开心',
          shareHook: '想说一句',
          occurredAt: DateTime.utc(2026, 8, 21),
        ),
      ],
      echoes: const [],
      manualRequest: false,
    );
    service.dispose();
    expect(prompt, contains('都不是必须条件'));
    expect(prompt, contains('不要仅因为事情普通'));
    expect(prompt, isNot(contains('高分瞬间通常至少具备两项')));
    expect(prompt, isNot(contains('为了发而发，没有具体细节')));
  });

  test(
    'retry instruction stays short and does not add a second rule block',
    () {
      final retry = EchoExpressionPrompt.userInstruction(avoidContent: '重复正文');
      expect(retry, '保持事实不变，换一种明显不同的表达方式。只输出正文。');
    },
  );
}
