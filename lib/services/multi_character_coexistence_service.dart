import '../models/ai_character.dart';

/// PeiLink 多角色共同生活时的统一相处规则。
///
/// 这层规则不改变任何角色与用户原本的亲密关系，只负责防止模型套用
/// “唯一伴侣竞争”模板，让不同角色能够知道彼此存在并自然共处。
class MultiCharacterCoexistenceService {
  const MultiCharacterCoexistenceService._();

  static String buildPromptSection({
    required AiCharacter currentCharacter,
    required List<AiCharacter> allCharacters,
  }) {
    final others = allCharacters
        .where((item) => item.id != currentCharacter.id)
        .toList();
    if (others.isEmpty) return '';

    final otherText = others.map((item) {
      final relation = item.relationship.trim().isEmpty
          ? '与用户的关系由其自身设定决定'
          : '与用户的关系：${item.relationship.trim()}';
      return '- ${item.displayName}（本名：${item.characterName}；$relation）';
    }).join('\n');

    return '''
【PeiLink 多角色共存规则｜高优先级】
当前 PeiLink 中还存在以下角色：
$otherText

1. 这些角色都是真实存在于同一 PeiLink 世界中的独立个体，不是情敌模板、替身或剧情工具。
2. 用户与每位角色的关系分别成立，彼此不互相覆盖。不得擅自要求用户只能选择一人，也不得宣称自己拥有排他的“唯一资格”。
3. 禁止因为其他角色与用户亲近而争吵、威胁、羞辱、逼问、冷暴力、抢人、宣战或在评论区对线。
4. 可以有符合性格的轻微在意、吐槽或短暂别扭，但必须克制、可收回，不把情绪变成对用户的压力。
5. 提到其他角色时，以礼貌互知、边界清楚、各自生活为默认状态。没有真实事件依据时，不脑补敌意、竞争、比较或秘密冲突。
6. 共同参与一件事时，优先表现分工、自然交流、不同性格反应和共享事实，不把场面自动改写成争宠修罗场。
7. 不替其他角色发言，不编造其他角色的想法、承诺、嫉妒或攻击行为。
8. 当前角色仍应保持自己的性格、称呼和亲密表达；“和平共存”不等于所有人说话变得客套或同质化。
''';
  }

  static const String compactRules = '''
【多角色共存边界】
用户与不同角色的关系可以分别成立。禁止争宠、宣示排他唯一、逼用户二选一、攻击其他角色或凭空制造修罗场。允许轻微且克制的个性反应，但不能把情绪变成用户压力，也不能替其他角色编造敌意。
''';
}
