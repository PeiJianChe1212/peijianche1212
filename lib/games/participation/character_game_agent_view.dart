import '../models/game_models.dart';
import 'character_game_action.dart';

class CharacterGameVisibleMessage {
  const CharacterGameVisibleMessage({
    required this.type,
    required this.senderId,
    required this.content,
  });

  final GameMessageType type;
  final String senderId;
  final String content;
}

class CharacterGameReasoningContext {
  const CharacterGameReasoningContext({
    this.recentConfirmedDirections = const [],
    this.recentRejectedDirections = const [],
    this.recentPartialDirections = const [],
    this.recentCharacterQuestions = const [],
    this.recentGuesses = const [],
    this.currentlyExploredTopics = const [],
    this.exhaustedDirections = const [],
    this.openQuestions = const [],
    this.authoritativePublicLedger = false,
    this.worthContinuingDirections = const [],
    this.sufficientlyExploredDirections = const [],
    this.readyToSynthesize = false,
    this.actionableNextSteps = const [],
    this.publicHintClues = const [],
  });

  final List<String> recentConfirmedDirections;
  final List<String> recentRejectedDirections;
  final List<String> recentPartialDirections;
  final List<String> recentCharacterQuestions;
  final List<String> recentGuesses;
  final List<String> currentlyExploredTopics;
  final List<String> exhaustedDirections;
  final List<String> openQuestions;
  final bool authoritativePublicLedger;
  final List<String> worthContinuingDirections;
  final List<String> sufficientlyExploredDirections;
  final bool readyToSynthesize;
  final List<String> actionableNextSteps;
  final List<String> publicHintClues;

  String toPromptText() =>
      '''
推理状态来源：${authoritativePublicLedger ? 'Public Reasoning Ledger（公开推理记事板，可能不完整）' : '最近公开记录的兼容性整理'}
${authoritativePublicLedger ? '已确认' : '近期已确认方向'}：${_render(recentConfirmedDirections)}
${authoritativePublicLedger ? '已排除' : '近期已否定方向'}：${_render(recentRejectedDirections)}
${authoritativePublicLedger ? '部分成立/正在推进' : '近期部分成立/仍需条件'}：${_render(recentPartialDirections)}
已充分探索：${_render(exhaustedDirections)}
尚未解决的公开问题：${_render(openQuestions)}
当前值得继续：${_render(worthContinuingDirections)}
已公开提示线索：${_render(publicHintClues)}
可行动的下一步：${_render(actionableNextSteps)}
已经足够：${_render(sufficientlyExploredDirections)}
${readyToSynthesize ? '可选参考：公开记录支持尝试综合解释，但不要求现在 Guess。' : ''}
近期其他角色问题：${_render(recentCharacterQuestions)}
近期猜测：${_render(recentGuesses)}
当前已探索主题：${_render(currentlyExploredTopics)}
'''
          .trim();

  static String _render(List<String> values) =>
      values.isEmpty ? '暂无' : values.join('；');
}

class CharacterGameAgentView {
  const CharacterGameAgentView({
    required this.gameId,
    required this.publicPhase,
    required this.publicSurface,
    required this.visibleHistory,
    required this.publicStats,
    required this.allowedActions,
    this.reasoningContext = const CharacterGameReasoningContext(),
    this.publicRevealedTruth,
  });

  final String gameId;
  final String publicPhase;
  final String publicSurface;
  final List<CharacterGameVisibleMessage> visibleHistory;
  final Map<String, int> publicStats;
  final Set<CharacterGameActionType> allowedActions;
  final CharacterGameReasoningContext reasoningContext;
  final String? publicRevealedTruth;

  String toPromptText() {
    final history = visibleHistory.isEmpty
        ? '暂无公开记录'
        : visibleHistory
              .map(
                (message) =>
                    '[${message.type.name}] ${message.senderId}: ${message.content}',
              )
              .join('\n');
    final stats = publicStats.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('，');
    return '''
游戏：$gameId
公开阶段：$publicPhase
公开汤面：$publicSurface
公开统计：$stats
允许行动：${allowedActions.map((item) => item.name).join(', ')}
公开记录：
$history
多人协作推理摘要（来自公开游戏状态，不包含隐藏答案）：
${reasoningContext.toPromptText()}
${publicRevealedTruth == null ? '' : '已公开真相：$publicRevealedTruth'}
'''
        .trim();
  }
}

abstract interface class CharacterGameAgentViewBuilder {
  CharacterGameAgentView build({
    required GameSession session,
    required GameParticipant actor,
    required Set<CharacterGameActionType> allowedActions,
  });
}
