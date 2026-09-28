import 'dart:math' as math;

import '../models/game_models.dart';
import 'character_game_action.dart';
import 'character_game_agent_view.dart';
import 'game_user_identity.dart';

class CharacterGameAgentRequest {
  const CharacterGameAgentRequest({
    required this.actorParticipantId,
    required this.characterId,
    required this.gameUserIdentity,
    required this.view,
    required this.allowedActions,
  });

  final String actorParticipantId;
  final String characterId;
  final GameUserIdentity gameUserIdentity;
  final CharacterGameAgentView view;
  final Set<CharacterGameActionType> allowedActions;
}

abstract interface class CharacterGameAgent {
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request);
}

class DeterministicCharacterGameAgent implements CharacterGameAgent {
  const DeterministicCharacterGameAgent({
    required this.actionType,
    this.content = '',
  });

  final CharacterGameActionType actionType;
  final String content;

  @override
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request) async {
    final type = request.allowedActions.contains(actionType)
        ? actionType
        : CharacterGameActionType.pass;
    return CharacterGameAction(
      actorParticipantId: request.actorParticipantId,
      type: type,
      content: type == CharacterGameActionType.pass ? '' : content,
    );
  }
}

class CharacterParticipationDecision {
  const CharacterParticipationDecision._({this.action, required this.reason});

  const CharacterParticipationDecision.action(CharacterGameAction action)
    : this._(action: action, reason: 'action');
  const CharacterParticipationDecision.pass([String reason = 'pass'])
    : this._(reason: reason);

  final CharacterGameAction? action;
  final String reason;
  bool get hasAction => action != null;
}

class CharacterParticipationRound {
  const CharacterParticipationRound({
    required this.roundId,
    required this.sessionId,
    required this.participantIds,
    this.turnIndex = 0,
  });

  final String roundId;
  final String sessionId;
  final List<String> participantIds;
  final int turnIndex;

  bool get isComplete => turnIndex >= participantIds.length;
  String? get currentParticipantId =>
      isComplete ? null : participantIds[turnIndex];

  CharacterParticipationRound advance() => CharacterParticipationRound(
    roundId: roundId,
    sessionId: sessionId,
    participantIds: participantIds,
    turnIndex: turnIndex + 1,
  );
}

class CharacterParticipationDirector {
  CharacterParticipationDirector({
    required this.agent,
    required this.legality,
    required this.viewBuilder,
    this.minimumInterval = const Duration(milliseconds: 750),
    bool Function(GameParticipant participant)? participantIsAvailable,
    DateTime Function()? clock,
  }) : _participantIsAvailable =
           participantIsAvailable ?? CharacterParticipationDirector._available,
       _clock = clock ?? DateTime.now;

  final CharacterGameAgent agent;
  final CharacterGameActionLegality legality;
  final CharacterGameAgentViewBuilder viewBuilder;
  final Duration minimumInterval;
  final bool Function(GameParticipant participant) _participantIsAvailable;
  final DateTime Function() _clock;

  bool _busy = false;
  DateTime? _lastOpportunityAt;
  int _candidateCursor = 0;
  int _roundCounter = 0;
  final Map<String, Set<String>> _claimedRoundTurns = {};

  CharacterParticipationRound startRound(GameSession session) {
    final candidates = session.status == GameSessionStatus.playing
        ? session.participants
              .where(_isValidCharacter)
              .where(_participantIsAvailable)
              .map((item) => item.participantId)
              .toList(growable: false)
        : const <String>[];
    final roundId = '${session.sessionId}:${_roundCounter++}';
    _claimedRoundTurns[roundId] = <String>{};
    if (_claimedRoundTurns.length > 8) {
      _claimedRoundTurns.remove(_claimedRoundTurns.keys.first);
    }
    return CharacterParticipationRound(
      roundId: roundId,
      sessionId: session.sessionId,
      participantIds: List.unmodifiable(candidates),
    );
  }

  /// [trigger] 为可选：User Action 驱动的 Round 传入真实 User GameAction；
  /// 「让他们继续」这类无 User Action 的手动触发传 null，表示没有用户动作触发。
  /// Director 当前不读取 trigger 内容，保留该参数仅为未来扩展预留。
  Future<CharacterParticipationDecision> offerTurn({
    required GameSession session,
    GameAction? trigger,
    required CharacterParticipationRound round,
  }) async {
    if (session.sessionId != round.sessionId) {
      return const CharacterParticipationDecision.pass('session-changed');
    }
    if (session.status != GameSessionStatus.playing) {
      return const CharacterParticipationDecision.pass('session-not-playing');
    }
    final participantId = round.currentParticipantId;
    if (participantId == null) {
      return const CharacterParticipationDecision.pass('round-complete');
    }
    final claimed = _claimedRoundTurns.putIfAbsent(round.roundId, () => {});
    if (!claimed.add(participantId)) {
      return const CharacterParticipationDecision.pass('turn-already-claimed');
    }
    final candidate = session.participants
        .where((item) => item.participantId == participantId)
        .where(_isValidCharacter)
        .where(_participantIsAvailable)
        .firstOrNull;
    if (candidate == null) {
      return const CharacterParticipationDecision.pass('candidate-unavailable');
    }
    return _decide(session: session, candidate: candidate);
  }

  Future<CharacterParticipationDecision> offerOpportunity({
    required GameSession session,
    required GameAction trigger,
  }) async {
    if (session.status != GameSessionStatus.playing) {
      return const CharacterParticipationDecision.pass('session-not-playing');
    }
    if (_busy) {
      return const CharacterParticipationDecision.pass('director-busy');
    }
    final now = _clock();
    final last = _lastOpportunityAt;
    if (last != null && now.difference(last) < minimumInterval) {
      return const CharacterParticipationDecision.pass('frequency-limited');
    }

    final candidates = session.participants
        .where(_isValidCharacter)
        .where(_participantIsAvailable)
        .toList();
    if (candidates.isEmpty) {
      return const CharacterParticipationDecision.pass('no-candidate');
    }

    _busy = true;
    _lastOpportunityAt = now;
    try {
      final candidate = candidates[_candidateCursor % candidates.length];
      _candidateCursor = (_candidateCursor + 1) % candidates.length;
      return await _decide(session: session, candidate: candidate);
    } finally {
      _busy = false;
    }
  }

  Future<CharacterParticipationDecision> _decide({
    required GameSession session,
    required GameParticipant candidate,
  }) async {
    final allowed = legality.allowedActions(session, candidate);
    if (allowed.isEmpty ||
        allowed.every((type) => type == CharacterGameActionType.pass)) {
      return const CharacterParticipationDecision.pass('no-legal-action');
    }
    CharacterGameAction action;
    try {
      final view = viewBuilder.build(
        session: session,
        actor: candidate,
        allowedActions: allowed,
      );
      action = await agent.decide(
        CharacterGameAgentRequest(
          actorParticipantId: candidate.participantId,
          characterId: candidate.characterId!,
          gameUserIdentity: GameUserIdentity.fromSession(session),
          view: view,
          allowedActions: Set.unmodifiable(allowed),
        ),
      );
    } catch (_) {
      return const CharacterParticipationDecision.pass('agent-failed');
    }
    if (action.actorParticipantId != candidate.participantId ||
        action.type == CharacterGameActionType.pass ||
        !allowed.contains(action.type)) {
      return const CharacterParticipationDecision.pass();
    }
    if (_RoundSemanticDuplicateGuard.isDuplicate(action, session.messages)) {
      return const CharacterParticipationDecision.pass('semantic-duplicate');
    }
    return CharacterParticipationDecision.action(action);
  }

  bool _isValidCharacter(GameParticipant participant) =>
      participant.type == GameParticipantType.character &&
      participant.participantId.trim().isNotEmpty &&
      (participant.characterId?.trim().isNotEmpty ?? false);

  static bool _available(GameParticipant participant) => true;
}

/// A deliberately conservative, local guard for the most obvious repeated
/// player turns. It is not a semantic judge: it only suppresses near-verbatim
/// actions of the same kind after the model has made its decision.
class _RoundSemanticDuplicateGuard {
  const _RoundSemanticDuplicateGuard._();

  static bool isDuplicate(
    CharacterGameAction action,
    List<GameMessage> messages,
  ) {
    final messageType = switch (action.type) {
      CharacterGameActionType.askQuestion => GameMessageType.question,
      CharacterGameActionType.makeGuess => GameMessageType.guess,
      CharacterGameActionType.react => GameMessageType.participant,
      CharacterGameActionType.pass => null,
    };
    if (messageType == null) return false;
    final candidate = _normalize(action.content);
    if (candidate.length < 8) return false;
    final recent = messages.reversed
        .where(
          (message) =>
              message.visibility == GameMessageVisibility.public &&
              message.type == messageType,
        )
        .take(8);
    return recent.any((message) {
      final previous = _normalize(message.content);
      if (previous.length < 8) return false;
      if (candidate == previous) return true;
      final lengthRatio =
          math.min(candidate.length, previous.length) /
          math.max(candidate.length, previous.length);
      if (lengthRatio >= .72 && _bigramDice(candidate, previous) >= .84) {
        return true;
      }
      return action.type == CharacterGameActionType.makeGuess &&
          _isRepeatedGuess(previous: previous, candidate: candidate);
    });
  }

  /// Guess 需要覆盖一条完整推理链。相比 Question，模型更容易保留大段
  /// 旧链、只替换开头同义词或追加很短的结尾；这种变化会显著降低 bigram
  /// Dice，却没有带来足够的新推理。LCS 保留内容顺序，因此不是关键词集合
  /// 重合判断。
  static bool _isRepeatedGuess({
    required String previous,
    required String candidate,
  }) {
    if (previous.length < 24 || candidate.length < 24) return false;
    final shared = _longestCommonSubsequenceLength(previous, candidate);
    if (shared < 24) return false;
    final previousCoverage = shared / previous.length;
    final candidateCoverage = shared / candidate.length;
    final candidateNovelty = 1 - candidateCoverage;
    return previousCoverage >= .67 &&
        candidateCoverage >= .67 &&
        candidateNovelty <= .33;
  }

  static String _normalize(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[\s\p{P}\p{S}]', unicode: true),
    '',
  );

  static double _bigramDice(String left, String right) {
    final a = _bigrams(left);
    final b = _bigrams(right);
    if (a.isEmpty || b.isEmpty) return 0;
    var overlap = 0;
    final remaining = <String, int>{};
    for (final token in b) {
      remaining[token] = (remaining[token] ?? 0) + 1;
    }
    for (final token in a) {
      final count = remaining[token] ?? 0;
      if (count > 0) {
        overlap++;
        remaining[token] = count - 1;
      }
    }
    return (2 * overlap) / (a.length + b.length);
  }

  static List<String> _bigrams(String value) => [
    for (var index = 0; index < value.length - 1; index++)
      value.substring(index, index + 2),
  ];

  static int _longestCommonSubsequenceLength(String left, String right) {
    var previous = List<int>.filled(right.length + 1, 0);
    for (var leftIndex = 1; leftIndex <= left.length; leftIndex++) {
      final current = List<int>.filled(right.length + 1, 0);
      for (var rightIndex = 1; rightIndex <= right.length; rightIndex++) {
        current[rightIndex] =
            left.codeUnitAt(leftIndex - 1) == right.codeUnitAt(rightIndex - 1)
            ? previous[rightIndex - 1] + 1
            : math.max(previous[rightIndex], current[rightIndex - 1]);
      }
      previous = current;
    }
    return previous.last;
  }
}
