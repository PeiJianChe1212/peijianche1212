import '../models/character_profile.dart';
import '../models/character_settings.dart';
import '../models/prompt_test_mode.dart';

class PromptTestContextBuilder {
  const PromptTestContextBuilder._();

  static String build({
    required PromptTestMode mode,
    required String memoryPrompt,
    required String transientEventContext,
    required CharacterProfile profile,
    required CharacterSettings settings,
  }) {
    final sections = <String>[
      _basicFacts(profile, settings),
      memoryPrompt.trim(),
      transientEventContext.trim(),
      if (mode == PromptTestMode.minimalRules) minimalRules,
    ].where((section) => section.isNotEmpty);
    return sections.join('\n\n');
  }

  static String _basicFacts(
    CharacterProfile profile,
    CharacterSettings settings,
  ) {
    String line(String label, String value) {
      final clean = value.trim();
      return clean.isEmpty ? '' : '$label：$clean';
    }

    final lines = <String>[
      line('年龄', profile.age),
      line('性别', profile.gender),
      line('身高', profile.height),
      line(
        '生日',
        profile.birthday.trim().isNotEmpty
            ? profile.birthday
            : settings.birthday,
      ),
      line('身份', profile.identity),
      line('职业', profile.occupation),
      line('所在地', profile.location),
    ].where((value) => value.isNotEmpty).join('\n');
    return lines.isEmpty ? '' : '【角色基础事实】\n$lines';
  }

  static const minimalRules = '''【极简聊天规则】
1. 严格按照角色人设、身份、经历和关系进行聊天。
2. 像真实的人一样自然交流，不要使用客服式、助手式或总结式语气。
3. 不要替用户说话，不要擅自决定用户的行为、心理或台词。
4. 不使用括号形式描写动作、神态或心理活动。
5. 可以自然表达角色自己的想法、生活、近况和话题，不必机械地只回答用户表面问题。
6. 不擅自改变角色设定、关系状态或已有事实。''';
}
