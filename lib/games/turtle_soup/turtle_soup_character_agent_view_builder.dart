import '../models/game_models.dart';
import '../participation/character_game_action.dart';
import '../participation/character_game_agent_view.dart';
import '../services/game_room_visibility.dart';
import 'turtle_soup_ledger_reasoning_context_builder.dart';
import 'turtle_soup_models.dart';
import 'turtle_soup_profile_registry.dart';

class TurtleSoupCharacterAgentViewBuilder
    implements CharacterGameAgentViewBuilder {
  const TurtleSoupCharacterAgentViewBuilder({
    this.historyLimit = 20,
    this.messageCharacterLimit = 500,
    this.ledgerReasoningContextBuilder =
        const TurtleSoupLedgerReasoningContextBuilder(),
  });

  final int historyLimit;
  final int messageCharacterLimit;
  final TurtleSoupLedgerReasoningContextBuilder ledgerReasoningContextBuilder;

  @override
  CharacterGameAgentView build({
    required GameSession session,
    required GameParticipant actor,
    required Set<CharacterGameActionType> allowedActions,
  }) {
    final state = session.gameState;
    if (state is! TurtleSoupState) {
      throw StateError('Turtle Soup Agent View requires TurtleSoupState.');
    }
    final visible = GameRoomVisibility.visibleMessagesFor(
      session,
      actor.participantId,
    );
    final history = visible
        .where(
          (message) => {
            GameMessageType.question,
            GameMessageType.answer,
            GameMessageType.hint,
            GameMessageType.guess,
            GameMessageType.participant,
          }.contains(message.type),
        )
        .toList(growable: false);
    final boundedHistory = history.length > historyLimit
        ? history.sublist(history.length - historyLimit)
        : history;
    final reasoningContext = _buildReasoningContext(session, state, visible);
    final revealedTruth =
        {
          TurtleSoupPhase.revealed,
          TurtleSoupPhase.finished,
        }.contains(state.phase)
        ? visible
              .where((message) => message.type == GameMessageType.reveal)
              .map((message) => message.content.trim())
              .where((content) => content.isNotEmpty)
              .lastOrNull
        : null;
    return CharacterGameAgentView(
      gameId: session.gameId,
      publicPhase: state.phase.name,
      publicSurface: _limit(state.surface),
      visibleHistory: boundedHistory
          .map(
            (message) => CharacterGameVisibleMessage(
              type: message.type,
              senderId: message.senderId,
              content: _limit(message.content),
            ),
          )
          .toList(growable: false),
      publicStats: {
        'questions': state.questionCount,
        'guesses': state.guessCount,
        'usedHints': state.usedHintCount,
        'totalHints': state.hints.length,
      },
      allowedActions: Set.unmodifiable(allowedActions),
      reasoningContext: reasoningContext,
      publicRevealedTruth: revealedTruth == null ? null : _limit(revealedTruth),
    );
  }

  CharacterGameReasoningContext _buildReasoningContext(
    GameSession session,
    TurtleSoupState state,
    List<GameMessage> visible,
  ) {
    final publicMessages = visible
        .where(
          (message) =>
              message.visibility == GameMessageVisibility.public &&
              {
                GameMessageType.question,
                GameMessageType.answer,
                GameMessageType.guess,
                GameMessageType.participant,
              }.contains(message.type),
        )
        .toList(growable: false);
    final characterParticipantIds = session.participants
        .where((item) => item.type == GameParticipantType.character)
        .map((item) => item.participantId)
        .toSet();
    final recentCharacterQuestions = publicMessages
        .where(
          (message) =>
              message.type == GameMessageType.question &&
              characterParticipantIds.contains(message.senderId),
        )
        .map((message) => _limit(message.content))
        .toList(growable: false);
    final recentGuesses = publicMessages
        .where((message) => message.type == GameMessageType.guess)
        .map((message) => _limit(message.content))
        .toList(growable: false);
    final profile = TurtleSoupProfileRegistry.findByPuzzleId(state.puzzleId);
    if (profile != null && state.reasoningLedger != null) {
      return ledgerReasoningContextBuilder.build(
        profile: profile,
        ledger: state.reasoningLedger!,
        recentCharacterQuestions: _recent(recentCharacterQuestions, 5),
        recentGuesses: _recent(recentGuesses, 4),
      );
    }

    final confirmed = <String>[];
    final rejected = <String>[];
    final partial = <String>[];
    final explored = <String>[];
    GameMessage? pendingInquiry;
    for (final message in publicMessages) {
      if (message.type == GameMessageType.question) {
        pendingInquiry = message;
        explored.add(_limit(message.content));
        continue;
      }
      if (message.type == GameMessageType.guess) {
        pendingInquiry = message;
        explored.add(_limit(message.content));
        continue;
      }
      if (message.type == GameMessageType.participant) {
        explored.add(_limit(message.content));
        continue;
      }
      if (message.type != GameMessageType.answer || pendingInquiry == null) {
        continue;
      }
      final direction =
          '${_limit(pendingInquiry.content)} → ${_limit(message.content)}';
      final response = message.content.trim().toLowerCase();
      if (response.contains('无法确定') || response.contains('无法直接判断')) {
        // Public uncertainty (including compound questions) is not evidence
        // for or against the player's proposition.
      } else if (_isRejected(response)) {
        rejected.add(direction);
      } else if (_isPartial(response)) {
        partial.add(direction);
      } else if (_isConfirmed(response)) {
        confirmed.add(direction);
      }
      pendingInquiry = null;
    }
    return CharacterGameReasoningContext(
      recentConfirmedDirections: _recent(confirmed, 4),
      recentRejectedDirections: _recent(rejected, 4),
      recentPartialDirections: _recent(partial, 4),
      recentCharacterQuestions: _recent(recentCharacterQuestions, 5),
      recentGuesses: _recent(recentGuesses, 4),
      currentlyExploredTopics: _recent(explored, 6),
    );
  }

  bool _isRejected(String value) =>
      value.contains('不是') ||
      value.contains('不对') ||
      value.contains('无关') ||
      value.contains('关系不大') ||
      value == '否';

  bool _isPartial(String value) =>
      value.contains('接近') ||
      value.contains('部分') ||
      value.contains('还缺') ||
      value.contains('方向');

  bool _isConfirmed(String value) =>
      value.contains('是') ||
      value.contains('正确') ||
      value.contains('有关') ||
      value == '对';

  List<String> _recent(List<String> values, int limit) => List.unmodifiable(
    values.length > limit ? values.sublist(values.length - limit) : values,
  );

  String _limit(String value) {
    final trimmed = value.trim();
    return trimmed.length <= messageCharacterLimit
        ? trimmed
        : trimmed.substring(0, messageCharacterLimit);
  }
}
