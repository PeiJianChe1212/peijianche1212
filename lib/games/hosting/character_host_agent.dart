import '../../models/ai_character.dart';
import '../../models/character_profile.dart';
import '../../services/character_profile_storage_service.dart';
import '../../services/character_registry_service.dart';
import '../../services/character_settings_storage_service.dart';
import '../models/game_models.dart';
import '../participation/game_user_identity.dart';

/// Engine 已经确定的权威主持语义。
///
/// Character Host 只能改写表达方式，判定本身只能来自 Engine（deterministic
/// 规则或 Semantic Judge 的结构化结果）。
enum GameHostSemanticType {
  /// 玩家陈述与汤底明确一致。
  answerYes,

  /// 玩家陈述与汤底明确冲突。
  answerNo,

  /// 问题可以理解，但对破解当前谜题没有实际关系。
  answerIrrelevant,

  /// 方向包含正确成分，但表述过宽或混入错误前提，不能直接回答 YES。
  answerPartial,

  /// 依据权威汤底确实无法判断，必须低频。
  answerUnknown,

  guessIncorrect,
  guessCorrect,
  hint,
  reveal,
}

class GameHostSemanticResult {
  const GameHostSemanticResult({
    required this.type,
    required this.canonicalText,
  });
  final GameHostSemanticType type;
  final String canonicalText;
}

class CharacterHostIdentity {
  const CharacterHostIdentity({
    required this.displayName,
    this.personalityTags = '',
    this.speakingStyle = '',
  });
  final String displayName;
  final String personalityTags;
  final String speakingStyle;
}

class CharacterHostKnowledgeView {
  const CharacterHostKnowledgeView({
    required this.gameId,
    required this.phase,
    required this.publicPuzzle,
    required this.hiddenTruth,
    required this.publicHistory,
    required this.triggerActorId,
    required this.triggerKind,
    required this.triggerContent,
    required this.semanticResult,
    required this.truthMayBeRevealed,
    this.protectedFacts = const [],
  });
  final String gameId;
  final String phase;
  final String publicPuzzle;
  final String hiddenTruth;
  final List<GameMessage> publicHistory;
  final String triggerActorId;
  final String triggerKind;
  final String triggerContent;
  final GameHostSemanticResult semanticResult;
  final bool truthMayBeRevealed;
  final List<String> protectedFacts;
}

class CharacterHostRenderRequest {
  const CharacterHostRenderRequest({
    required this.sessionId,
    required this.responseMessageId,
    required this.characterId,
    required this.identity,
    required this.gameUserIdentity,
    required this.view,
  });
  final String sessionId;
  final String responseMessageId;
  final String characterId;
  final CharacterHostIdentity identity;
  final GameUserIdentity gameUserIdentity;
  final CharacterHostKnowledgeView view;
}

abstract interface class CharacterHostResponseRenderer {
  Future<String> render(CharacterHostRenderRequest request);
}

class DeterministicCharacterHostResponseRenderer
    implements CharacterHostResponseRenderer {
  const DeterministicCharacterHostResponseRenderer();
  @override
  Future<String> render(CharacterHostRenderRequest request) async =>
      request.view.semanticResult.canonicalText;
}

typedef CharacterHostIdentityLoader =
    Future<CharacterHostIdentity?> Function(String characterId);

class SafeCharacterHostIdentityLoader {
  const SafeCharacterHostIdentityLoader();

  Future<CharacterHostIdentity?> call(String characterId) async {
    final character = (await CharacterRegistryService().loadCharacters())
        .where((item) => item.id == characterId)
        .firstOrNull;
    if (character == null) return null;
    final settings = await CharacterSettingsStorageService(
      characterId: character.id,
    ).loadSettings();
    final profile = await CharacterProfileStorageService(
      characterId: character.id,
    ).load(character: character, legacySettings: settings);
    return identityFrom(character, profile);
  }

  static CharacterHostIdentity identityFrom(
    AiCharacter character,
    CharacterProfile profile,
  ) => CharacterHostIdentity(
    displayName: character.displayName,
    personalityTags: profile.personalityTags,
    speakingStyle: profile.speakingStyle,
  );
}
