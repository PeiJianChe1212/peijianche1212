import '../models/ai_character.dart';
import '../models/relationship_boundary.dart';

/// PeiLink 内所有角色共同遵守的社交协议。
///
/// 这不是角色人设的一部分，而是系统级边界。无论新增多少角色，
/// 聊天、生活、Echo 与评论都从同一个入口读取规则，避免各模块分叉。
class AiSocialProtocolService {
  const AiSocialProtocolService._();

  static RelationshipBoundary boundaryFor(AiCharacter character) {
    return RelationshipBoundary(characterId: character.id);
  }

  static List<String> sanitizeRelatedCharacterNames({
    required Iterable<String> requestedNames,
    required AiCharacter currentCharacter,
    required List<AiCharacter> allCharacters,
    int maxCount = 1,
  }) {
    final allowed = <String, String>{};
    for (final item in allCharacters) {
      if (item.id == currentCharacter.id) continue;
      for (final raw in [item.displayName, item.characterName]) {
        final name = raw.trim();
        if (name.isNotEmpty) allowed[name] = name;
      }
    }

    final result = <String>[];
    for (final raw in requestedNames) {
      final name = raw.trim();
      final safe = allowed[name];
      if (safe == null || result.contains(safe)) continue;
      result.add(safe);
      if (result.length >= maxCount) break;
    }
    return result;
  }

  static String buildPromptSection({
    required AiCharacter currentCharacter,
    required List<AiCharacter> allCharacters,
  }) {
    final others = allCharacters
        .where((item) => item.id != currentCharacter.id)
        .toList();
    if (others.isEmpty) return '';

    final names = others.map((item) => item.displayName).join('、');
    return '''
【PeiLink AI 社交协议｜系统级高优先级】
当前角色：${currentCharacter.displayName}
同一世界中的其他角色：$names

一、身份与边界
1. 每位角色都是独立个体，拥有各自的人设、记忆、聊天记录和与用户分别成立的关系。
2. 当前角色只能读取系统明确提供的共同经历、关系摘要和公开 Echo；不得假装看过其他角色的私聊、私人记忆或未公开想法。
3. 不得替其他角色说话、承诺、道歉、吃醋或作决定，也不得冒充其他角色。

二、多伴侣共存
4. 用户与不同角色的亲密关系可以同时成立，不互相覆盖。
5. 禁止宣示排他唯一、逼用户二选一、比较谁更重要、抢人、威胁、羞辱、冷暴力或把其他角色当作竞争者。
6. 允许符合性格的轻微在意、吐槽或短暂别扭，但必须克制、可收回，不能给用户制造压力。

三、共同生活
7. 只有系统提供的共同事件和关系记忆可以成为共同过去；不得伪造私下联系、旧矛盾、秘密约定或多年交情。
8. 多人事件优先表现自然分工、不同反应、礼貌边界和逐渐形成的默契，不自动生成修罗场。
9. 关系阶段只能依据真实经历缓慢变化；一次普通碰面不能突然成为挚友或宿敌。

四、公开互动
10. Echo 与评论区允许自然提及其他角色，但不得公开窥探隐私、替人表态、阴阳怪气、宣战或借题争宠。
11. 角色可以保持鲜明个性。遵守协议不等于客套、同质化或失去亲密表达。
''';
  }

  static const String compactRules = '''
【AI 社交协议】
各角色的身份、记忆和与用户的关系彼此独立。只能使用系统提供的共同经历与关系摘要，不得偷看或编造其他角色私聊和想法，不得替人发言、冒充、宣示排他唯一、逼用户选择、争宠攻击或制造修罗场。多人互动应保持个性差异、自然分工和清楚边界。
''';
}
