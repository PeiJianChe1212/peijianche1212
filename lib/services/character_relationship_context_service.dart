import '../models/ai_character.dart';
import 'relationship_network_service.dart';

class CharacterRelationshipContextService {
  CharacterRelationshipContextService({
    RelationshipNetworkService? networkService,
  }) : _networkService = networkService ?? RelationshipNetworkService();

  final RelationshipNetworkService _networkService;

  Future<String> buildPromptSection({
    required AiCharacter currentCharacter,
    required List<AiCharacter> allCharacters,
  }) async {
    final others = allCharacters
        .where((item) => item.id != currentCharacter.id)
        .toList();
    if (others.isEmpty) return '';

    final snapshot = await _networkService.buildSnapshot(
      characters: allCharacters,
    );
    final lines = _networkService.buildCompactContext(
      snapshot: snapshot,
      currentCharacterId: currentCharacter.id,
    );
    if (lines.trim().isEmpty) return '';

    return '''
【角色关系网络中的已记录状态】
$lines

这些内容由关系阶段、真实共同经历和关系记忆统一整理：
1. 不得无依据把“知道彼此存在”写成多年好友，也不得突然写成宿敌。
2. 关系可以缓慢升温，但一次普通碰面不能跳过多个阶段。
3. “能够合作”不等于亲密，“朋友”也不改变各角色与用户各自成立的关系。
4. 没有共同事件时，不编造私下联系、共同回忆、秘密约定或旧矛盾。
5. 最近记忆和相处规律只能自然引用，不能逐条背诵或伪造细节。
6. 后台维度不代表公开分数，不得在回复里说关系值、好感度或百分比。
''';
  }

  /// V2 Facts 专用：只输出关系网络快照，不附加关系推进策略。
  Future<String> buildFactsSection({
    required AiCharacter currentCharacter,
    required List<AiCharacter> allCharacters,
  }) async {
    final others = allCharacters
        .where((item) => item.id != currentCharacter.id)
        .toList();
    if (others.isEmpty) return '';
    final snapshot = await _networkService.buildSnapshot(
      characters: allCharacters,
    );
    final lines = _networkService.buildCompactContext(
      snapshot: snapshot,
      currentCharacterId: currentCharacter.id,
    );
    return lines.trim().isEmpty
        ? ''
        : '【Character Facts｜角色关系网络】\n${lines.trim()}';
  }
}
