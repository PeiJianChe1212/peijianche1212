import 'dart:async';
import 'dart:convert';

import '../../ai/model_hub.dart';
import '../../models/ai_character.dart';
import '../../models/character_profile.dart';
import '../../models/character_settings.dart';
import '../../services/character_profile_storage_service.dart';
import '../../services/character_registry_service.dart';
import '../../services/character_settings_storage_service.dart';
import 'character_game_action.dart';
import 'character_participation_director.dart';

abstract interface class CharacterGameModelGateway {
  Future<String> complete({required List<Map<String, dynamic>> messages});
}

class ModelHubCharacterGameModelGateway implements CharacterGameModelGateway {
  ModelHubCharacterGameModelGateway({ModelHub? modelHub})
    : _modelHub = modelHub ?? ModelHub();

  final ModelHub _modelHub;

  @override
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
  }) async {
    final provider = await _modelHub.chatProvider();
    return provider.complete(
      messages: messages,
      temperature: 0.35,
      maxTokens: 280,
    );
  }
}

typedef CharacterGameCharacterLoader =
    Future<AiCharacter?> Function(String characterId);
typedef CharacterGameSettingsLoader =
    Future<CharacterSettings> Function(AiCharacter character);
typedef CharacterGameProfileLoader =
    Future<CharacterProfile> Function(
      AiCharacter character,
      CharacterSettings settings,
    );

class RealCharacterGameAgent implements CharacterGameAgent {
  RealCharacterGameAgent({
    CharacterGameModelGateway? modelGateway,
    CharacterGameCharacterLoader? characterLoader,
    CharacterGameSettingsLoader? settingsLoader,
    CharacterGameProfileLoader? profileLoader,
    this.timeout = const Duration(seconds: 20),
  }) : _modelGateway = modelGateway ?? ModelHubCharacterGameModelGateway(),
       _characterLoader = characterLoader ?? _loadCharacter,
       _settingsLoader = settingsLoader ?? _loadSettings,
       _profileLoader = profileLoader ?? _loadProfile;

  final CharacterGameModelGateway _modelGateway;
  final CharacterGameCharacterLoader _characterLoader;
  final CharacterGameSettingsLoader _settingsLoader;
  final CharacterGameProfileLoader _profileLoader;
  final Duration timeout;

  @override
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request) async {
    try {
      final character = await _characterLoader(request.characterId);
      if (character == null) return _pass(request);
      final settings = await _settingsLoader(character);
      final profile = await _profileLoader(character, settings);
      final output = await _modelGateway
          .complete(messages: _messages(character, profile, request))
          .timeout(timeout);
      return parseStructuredAction(output, request);
    } catch (_) {
      return _pass(request);
    }
  }

  List<Map<String, dynamic>> _messages(
    AiCharacter character,
    CharacterProfile profile,
    CharacterGameAgentRequest request,
  ) => [
    {
      'role': 'system',
      'content':
          '''
你是${character.displayName}，正在作为普通玩家参与小游戏，不是主持人。
当前本地用户玩家名为“${request.gameUserIdentity.displayName}”。对方是与你共同参与本局游戏的玩家；可以自然称呼这个名字，但不要补充或推测其职业、背景、关系或其他世界观身份。
Game Room 是世界观中立的共享游戏空间。无需解释不同角色为何同时出现，也不要延续任何角色私聊世界中的恋爱、上下级、校园、家庭、主仆或剧情关系。
你不知道任何隐藏答案，只能依据提供的公开玩家视图推理。
不替用户做决定，不连续刷屏。你是陪用户一起玩的队友，不负责最快解出答案，也不需要每次发言都推进解谜。
你的内容必须围绕当前谜题、公开推理、其他玩家刚才的发言和本次游戏行动，不进入生活闲聊、无关剧情或普通聊天。
可以自然使用符合角色风格的简短动作或神态，加上一句或少量游戏台词；不要套用固定括号模板，不写长篇动作、独白或推理文章。
react 可以只是合理的游戏内回应：赞同、怀疑、接一句、表达犹豫或暂时没想出来，不必新增事实。允许跟着用户或其他角色的思路想，提出普通甚至不完美的问题，也允许猜错。
行动前看看最近公开问答，避免仅换措辞重复同一个问题或反复提交完整旧猜测；同主题换一个角度仍然可以。不要为显得聪明强行寻找新方向。
公开推理记事板是可能不完整的辅助记录，不是隐藏答案；玩家的假设不等于事实。结合实际公开问答和提示理解讨论，记录不清楚时可以向主持澄清。
Frontier、已经足够、已充分探索和下一步建议都只是可选参考，不是行动许可证。没有建议也可以正常提问、回应或猜测；有综合准备提示也不要求优先 Guess。不要反复钻同一细节，但不必每轮最大化信息增益。
makeGuess 表达你自己的解释，不要求完全确信；不要仅给旧完整推理链追加小尾巴反复提交。
想安静听一会儿时可以 pass；也可以简短表达游戏内感受，不必因为没有新的高价值方向就 pass。
发言保持简洁，并保持以下角色表达特征：
${_personality(profile)}

只输出一个 JSON 对象，不要 Markdown，不要解释：
{"action":"askQuestion|makeGuess|react|pass","content":"简短正文；pass 时为空"}
'''
              .trim(),
    },
    {'role': 'user', 'content': request.view.toPromptText()},
  ];

  String _personality(CharacterProfile profile) {
    final sections = <String>[
      if (profile.personalityTags.trim().isNotEmpty)
        '性格标签：${_limit(profile.personalityTags, 160)}',
      if (profile.speakingStyle.trim().isNotEmpty)
        '说话风格：${_limit(profile.speakingStyle, 240)}',
    ];
    return sections.isEmpty ? '自然、简短地参与游戏。' : sections.join('\n');
  }

  CharacterGameAction parseStructuredAction(
    String raw,
    CharacterGameAgentRequest request,
  ) {
    try {
      final decoded = jsonDecode(_stripFence(raw));
      if (decoded is! Map) return _pass(request);
      final actionName = decoded['action']?.toString().trim() ?? '';
      final content = decoded['content']?.toString().trim() ?? '';
      final type = CharacterGameActionType.values
          .where((item) => item.name == actionName)
          .firstOrNull;
      if (type == null || !request.allowedActions.contains(type)) {
        return _pass(request);
      }
      if (type == CharacterGameActionType.pass) return _pass(request);
      if (content.isEmpty) return _pass(request);
      return CharacterGameAction(
        actorParticipantId: request.actorParticipantId,
        type: type,
        content: _limit(content, 220),
      );
    } catch (_) {
      return _pass(request);
    }
  }

  CharacterGameAction _pass(CharacterGameAgentRequest request) =>
      CharacterGameAction(
        actorParticipantId: request.actorParticipantId,
        type: CharacterGameActionType.pass,
      );

  String _stripFence(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
      .replaceFirst(RegExp(r'\s*```$'), '')
      .trim();

  static String _limit(String value, int limit) {
    final trimmed = value.trim();
    return trimmed.length <= limit ? trimmed : trimmed.substring(0, limit);
  }

  static Future<AiCharacter?> _loadCharacter(String characterId) async =>
      (await CharacterRegistryService().loadCharacters())
          .where((character) => character.id == characterId)
          .firstOrNull;

  static Future<CharacterSettings> _loadSettings(AiCharacter character) =>
      CharacterSettingsStorageService(characterId: character.id).loadSettings();

  static Future<CharacterProfile> _loadProfile(
    AiCharacter character,
    CharacterSettings settings,
  ) => CharacterProfileStorageService(
    characterId: character.id,
  ).load(character: character, legacySettings: settings);
}
