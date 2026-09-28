import '../engines/game_engine.dart';
import '../hosting/character_host_agent.dart';
import '../models/game_models.dart';
import '../participation/character_game_action.dart';
import '../participation/game_user_identity.dart';
import '../services/game_room_visibility.dart';
import 'turtle_soup_character_participation_adapter.dart';
import 'turtle_soup_logic_profile.dart';
import 'turtle_soup_models.dart';
import 'turtle_soup_hint_reasoning_bridge.dart';
import 'turtle_soup_profile_registry.dart';
import 'turtle_soup_puzzle_registry.dart';
import 'turtle_soup_reasoning_ledger.dart';
import 'turtle_soup_reasoning_reducer.dart';
import 'turtle_soup_semantic_decision.dart';
import 'turtle_soup_semantic_judge.dart';
import 'turtle_soup_guess_decision.dart';

class TurtleSoupEngine implements GameEngine<TurtleSoupState> {
  const TurtleSoupEngine({
    this.hostRenderer,
    this.hostIdentityLoader,
    this.semanticJudge,
  });
  final CharacterHostResponseRenderer? hostRenderer;
  final CharacterHostIdentityLoader? hostIdentityLoader;

  /// Engine authoritative Semantic Judge。Character Host 只负责表达，
  /// 判定只能由 deterministic 规则或这里返回的结构化结果决定。
  final TurtleSoupSemanticJudge? semanticJudge;

  @override
  Future<GameResult<GameSession>> initializeSession(GameSession session) async {
    if (session.gameState is TurtleSoupState) {
      return GameResult.success(session);
    }
    final requested = (session.gameState is BaseGameState)
        ? (session.gameState as BaseGameState).participantState['puzzleId']
              ?.toString()
        : null;
    final puzzle = requested == null || requested.isEmpty
        ? TurtleSoupPuzzleRegistry.randomForParticipants(
            session.participants.length,
          )
        : TurtleSoupPuzzleRegistry.byId(requested);
    return GameResult.success(session.copyWith(gameState: _stateFor(puzzle)));
  }

  TurtleSoupState _stateFor(TurtleSoupPuzzle puzzle) {
    final profile = TurtleSoupProfileRegistry.findByPuzzleId(puzzle.id);
    return TurtleSoupState(
      puzzleId: puzzle.id,
      title: puzzle.title,
      surface: puzzle.surface,
      truth: puzzle.truth,
      hints: puzzle.hints,
      reasoningLedger: profile == null
          ? null
          : PublicReasoningLedger(profileVersion: profile.version),
    );
  }

  Future<GameResult<GameSession>> playAgain(GameSession session) async {
    final current = session.gameState;
    if (current is! TurtleSoupState ||
        !{
          TurtleSoupPhase.revealed,
          TurtleSoupPhase.finished,
        }.contains(current.phase)) {
      return const GameResult(
        GameResultCode.invalidState,
        message: '当前还不能再来一局。',
      );
    }
    final puzzle = TurtleSoupPuzzleRegistry.randomForParticipantsExcluding(
      session.participants.length,
      current.puzzleId,
    );
    return GameResult.success(
      session.copyWith(
        status: GameSessionStatus.playing,
        gameState: _stateFor(puzzle).copyWith(
          phase: TurtleSoupPhase.questioning,
          startedAt: DateTime.now(),
        ),
        messages: const [],
      ),
    );
  }

  @override
  Future<GameResult<List<GameEvent>>> startGame(GameSession session) async {
    final state = session.gameState;
    if (state is! TurtleSoupState || state.phase != TurtleSoupPhase.ready) {
      return const GameResult(
        GameResultCode.invalidState,
        message: '这个房间现在不能开始。',
      );
    }
    final next = state.copyWith(
      phase: TurtleSoupPhase.questioning,
      startedAt: DateTime.now(),
    );
    return GameResult.success([
      GameEvent(type: GameEventType.sessionStarted, state: next),
      GameEvent(
        type: GameEventType.messageAdded,
        message: _message(session, GameMessageType.puzzle, state.surface),
      ),
    ]);
  }

  @override
  Future<GameResult<List<GameEvent>>> handleUserAction(
    GameSession session,
    GameAction action,
  ) async {
    final state = session.gameState;
    if (state is! TurtleSoupState ||
        {
          TurtleSoupPhase.revealed,
          TurtleSoupPhase.finished,
        }.contains(state.phase)) {
      return const GameResult(GameResultCode.invalidState, message: '本局已经结束。');
    }
    final kind = action.payload['kind']?.toString();
    final text = action.payload['text']?.toString().trim() ?? '';
    switch (kind) {
      case 'question':
        if (text.isEmpty) return _emptyInput();
        return _question(session, state, text, action.actorParticipantId);
      case 'guess':
        if (text.isEmpty) return _emptyInput();
        return _guess(session, state, text, action.actorParticipantId);
      case 'hint':
        return _hint(session, state, action.actorParticipantId);
      case 'reveal':
        return _reveal(
          session,
          state,
          solved: false,
          actor: action.actorParticipantId,
        );
      default:
        return const GameResult(GameResultCode.invalidAction, message: '未知操作。');
    }
  }

  GameResult<List<GameEvent>> _emptyInput() =>
      const GameResult(GameResultCode.invalidAction, message: '先输入你的问题或推理。');

  Future<GameResult<List<GameEvent>>> _question(
    GameSession session,
    TurtleSoupState state,
    String text,
    String actor,
  ) async {
    final decision = await _questionSemantic(session, state, text);
    final semantic = decision.judgment.semanticResult;
    final turn = state.questionCount + 1;
    final provenanceBase = '${session.sessionId}-$turn-$actor';
    final questionMessageId = 'question-$provenanceBase';
    final answerMessageId = 'answer-$provenanceBase';
    final response = await _renderHostResponse(
      session,
      state,
      actor: actor,
      kind: 'question',
      content: text,
      semantic: semantic,
      responseMessageId: answerMessageId,
    );
    final questionMessage = _message(
      session,
      GameMessageType.question,
      text,
      sender: actor,
      id: questionMessageId,
    );
    final answerMessage = _message(
      session,
      GameMessageType.answer,
      response.$1,
      id: response.$2 ?? answerMessageId,
    );
    final profile = TurtleSoupProfileRegistry.findByPuzzleId(state.puzzleId);
    var reasoningLedger = state.reasoningLedger;
    if (profile != null) {
      final current =
          reasoningLedger ??
          PublicReasoningLedger(profileVersion: profile.version);
      try {
        reasoningLedger = const TurtleSoupReasoningReducer().reduce(
          current: current,
          decision: decision,
          question: text,
          canonicalAnswer: decision.judgment.canonicalText,
          provenanceMessageIds: [questionMessage.id, answerMessage.id],
          currentTurn: turn,
          profile: profile,
        );
      } catch (_) {
        // Reasoning metadata is strictly best-effort. It must never prevent a
        // valid question and canonical Host response from completing.
        reasoningLedger = current;
      }
    }
    final next = state.copyWith(
      questionCount: state.questionCount + 1,
      phase: TurtleSoupPhase.questioning,
      reasoningLedger: reasoningLedger,
    );
    return GameResult.success([
      GameEvent(type: GameEventType.stateChanged, state: next),
      GameEvent(type: GameEventType.messageAdded, message: questionMessage),
      GameEvent(type: GameEventType.messageAdded, message: answerMessage),
    ]);
  }

  /// deterministic-first：只有唯一且明确的规则命中才直接判定；
  /// 没有命中或命中互相冲突时，交给 Semantic Judge。
  ///
  /// 旧实现只做关键词 contains，未命中就无条件回答 UNKNOWN，
  /// 导致大量正常、具体的自然语言问题无法参与推理。
  Future<TurtleSoupSemanticDecision> _questionSemantic(
    GameSession session,
    TurtleSoupState state,
    String question,
  ) async {
    final puzzle = TurtleSoupPuzzleRegistry.byId(state.puzzleId);
    final profile = TurtleSoupProfileRegistry.findByPuzzleId(state.puzzleId);
    if (profile != null) {
      final boundary = const TurtleSoupBoundaryDecisionMatcher().match(
        profile,
        question,
      );
      if (boundary != null) return boundary;
      final judged = await _modelQuestionDecision(
        session,
        puzzle,
        profile,
        question,
      );
      return judged ??
          const TurtleSoupSemanticDecision(
            judgment: TurtleSoupJudgment.uncertain,
          );
    }

    final deterministic = _deterministicQuestionSemantic(puzzle, question);
    if (deterministic != null) {
      return TurtleSoupSemanticDecision(judgment: deterministic);
    }
    final judged = await _modelQuestionSemantic(session, puzzle, question);
    return TurtleSoupSemanticDecision(
      judgment: judged ?? TurtleSoupJudgment.uncertain,
    );
  }

  /// 返回 null 表示 deterministic 规则无法可靠判断，需要 Semantic Judge。
  TurtleSoupJudgment? _deterministicQuestionSemantic(
    TurtleSoupPuzzle puzzle,
    String question,
  ) {
    final value = question.toLowerCase();
    final matches = <TurtleSoupJudgment>[
      if (_containsAny(value, puzzle.noKeywords)) TurtleSoupJudgment.no,
      if (_containsAny(value, puzzle.yesKeywords)) TurtleSoupJudgment.yes,
      if (_containsAny(value, puzzle.irrelevantKeywords))
        TurtleSoupJudgment.irrelevant,
    ];
    // 命中多个方向说明问题混入了互相冲突的前提，关键词规则不再可靠。
    return matches.length == 1 ? matches.single : null;
  }

  Future<TurtleSoupJudgment?> _modelQuestionSemantic(
    GameSession session,
    TurtleSoupPuzzle puzzle,
    String question,
  ) async {
    final judge = semanticJudge;
    if (judge == null) return null;
    try {
      final judgment = await judge.judge(
        TurtleSoupJudgeRequest(
          puzzle: puzzle,
          question: question,
          recentPublicContext: _recentPublicQuestionContext(session),
        ),
      );
      return judgment;
    } catch (_) {
      // Judge 异常等同于无法判定：交回 canonical 兜底，绝不打断本局。
      return null;
    }
  }

  Future<TurtleSoupSemanticDecision?> _modelQuestionDecision(
    GameSession session,
    TurtleSoupPuzzle puzzle,
    TurtleSoupLogicProfile profile,
    String question,
  ) async {
    final judge = semanticJudge;
    if (judge == null) return null;
    final request = TurtleSoupJudgeRequest(
      puzzle: puzzle,
      question: question,
      recentPublicContext: _recentPublicQuestionContext(session),
    );
    try {
      if (judge is TurtleSoupSemanticDecisionJudge) {
        final decision = await (judge as TurtleSoupSemanticDecisionJudge)
            .judgeDecision(request, profile);
        if (decision == null) return null;
        final validated = const TurtleSoupDecisionEffectValidator().validate(
          profile: profile,
          judgment: decision.judgment,
          effects: decision.effects,
        );
        return TurtleSoupSemanticDecision(
          judgment: decision.judgment,
          effects: validated.length == decision.effects.length
              ? validated
              : const [],
        );
      }
      final judgment = await judge.judge(request);
      return judgment == null
          ? null
          : TurtleSoupSemanticDecision(judgment: judgment);
    } catch (_) {
      return null;
    }
  }

  /// 只收集公开问答上下文；汤底与真相要点只进入 Judge 请求。
  List<String> _recentPublicQuestionContext(
    GameSession session,
  ) => GameRoomVisibility.visibleMessages(session)
      .where(
        (message) => const {
          GameMessageType.question,
          GameMessageType.answer,
          GameMessageType.guess,
          GameMessageType.hint,
          GameMessageType.participant,
        }.contains(message.type),
      )
      .toList(growable: false)
      .reversed
      .take(6)
      .toList(growable: false)
      .reversed
      .map(
        (message) =>
            '${message.type.name} ${message.senderId}: ${_limitContext(message.content)}',
      )
      .toList(growable: false);

  String _limitContext(String value) {
    final trimmed = value.trim();
    return trimmed.length <= 120 ? trimmed : trimmed.substring(0, 120);
  }

  Future<GameResult<List<GameEvent>>> _guess(
    GameSession session,
    TurtleSoupState state,
    String text,
    String actor,
  ) async {
    final puzzle = TurtleSoupPuzzleRegistry.byId(state.puzzleId);
    var solved = false;
    final judge = semanticJudge;
    if (judge is TurtleSoupGuessJudge) {
      try {
        solved = await (judge as TurtleSoupGuessJudge).judgeGuess(
          TurtleSoupGuessRequest(
            puzzle: puzzle,
            guess: text,
            profile: TurtleSoupProfileRegistry.findByPuzzleId(state.puzzleId),
          ),
        );
      } catch (_) {
        /* An unavailable judge cannot award a win. */
      }
    }
    final semantic = GameHostSemanticResult(
      type: solved
          ? GameHostSemanticType.guessCorrect
          : GameHostSemanticType.guessIncorrect,
      canonicalText: solved ? '答对了！你还原了故事的关键。' : '这次还未确认完整解法，可以继续梳理关键因果后尝试。',
    );
    final reply = await _renderHostResponse(
      session,
      state,
      actor: actor,
      kind: 'guess',
      content: text,
      semantic: semantic,
    );
    final revealText = solved
        ? await _renderHostResponse(
            session,
            state,
            actor: actor,
            kind: 'reveal',
            content: '',
            semantic: GameHostSemanticResult(
              type: GameHostSemanticType.reveal,
              canonicalText: state.truth,
            ),
            truthMayBeRevealed: true,
          )
        : null;
    final next = state.copyWith(
      guessCount: state.guessCount + 1,
      phase: solved ? TurtleSoupPhase.finished : TurtleSoupPhase.questioning,
      isSolved: solved,
      finishedAt: solved ? DateTime.now() : null,
      solvedByParticipantId: solved ? actor : null,
    );
    return GameResult.success([
      GameEvent(type: GameEventType.stateChanged, state: next),
      GameEvent(
        type: GameEventType.messageAdded,
        message: _message(session, GameMessageType.guess, text, sender: actor),
      ),
      GameEvent(
        type: GameEventType.messageAdded,
        message: _message(
          session,
          GameMessageType.answer,
          reply.$1,
          id: reply.$2,
        ),
      ),
      if (solved)
        GameEvent(
          type: GameEventType.messageAdded,
          message: _message(
            session,
            GameMessageType.reveal,
            revealText?.$1 ?? state.truth,
            id: revealText?.$2,
          ),
        ),
      if (solved) GameEvent(type: GameEventType.gameFinished, state: next),
    ]);
  }

  Future<(String, String?)> _renderHostResponse(
    GameSession session,
    TurtleSoupState state, {
    required String actor,
    required String kind,
    required String content,
    required GameHostSemanticResult semantic,
    bool truthMayBeRevealed = false,
    String? responseMessageId,
  }) async {
    if (session.host.type != GameHostType.characterHost) {
      return (semantic.canonicalText, null);
    }
    final renderer = hostRenderer;
    final characterId = session.host.characterId;
    if (renderer == null || characterId == null) {
      return (semantic.canonicalText, null);
    }
    try {
      final stableResponseMessageId =
          responseMessageId ?? 'host-${DateTime.now().microsecondsSinceEpoch}';
      final identity = CharacterHostIdentity(
        displayName: _hostFallbackName(session, characterId),
      );
      final visibleHistory = GameRoomVisibility.visibleMessages(session);
      final rendered = (await renderer.render(
        CharacterHostRenderRequest(
          sessionId: session.sessionId,
          responseMessageId: stableResponseMessageId,
          characterId: characterId,
          identity: identity,
          gameUserIdentity: GameUserIdentity.fromSession(session),
          view: CharacterHostKnowledgeView(
            gameId: session.gameId,
            phase: state.phase.name,
            publicPuzzle: state.surface,
            hiddenTruth: state.truth,
            publicHistory: visibleHistory,
            triggerActorId: actor,
            triggerKind: kind,
            triggerContent: content,
            semanticResult: semantic,
            truthMayBeRevealed: truthMayBeRevealed,
            protectedFacts: TurtleSoupPuzzleRegistry.byId(
              state.puzzleId,
            ).requiredTruthPoints,
          ),
        ),
      )).trim();
      if (rendered.isEmpty ||
          rendered.length > 220 ||
          (_leaksTruth(rendered, state) && !truthMayBeRevealed)) {
        return (semantic.canonicalText, null);
      }
      return (rendered, stableResponseMessageId);
    } catch (_) {
      return (semantic.canonicalText, null);
    }
  }

  String _hostFallbackName(GameSession session, String characterId) =>
      session.participants
          .where((item) => item.characterId == characterId)
          .map((item) => item.displayName)
          .firstOrNull ??
      '角色主持人';

  Future<GameResult<List<GameEvent>>> _hint(
    GameSession session,
    TurtleSoupState state,
    String actor,
  ) async {
    if (state.usedHintCount >= state.hints.length) {
      return const GameResult(
        GameResultCode.invalidAction,
        message: '提示已经用完了。',
      );
    }
    final hint = state.hints[state.usedHintCount];
    final response = await _renderHostResponse(
      session,
      state,
      actor: actor,
      kind: 'hint',
      content: '',
      semantic: GameHostSemanticResult(
        type: GameHostSemanticType.hint,
        canonicalText: hint,
      ),
    );
    final message = _message(
      session,
      GameMessageType.hint,
      response.$1,
      id: response.$2,
    );
    var ledger = state.reasoningLedger;
    final profile = TurtleSoupProfileRegistry.findByPuzzleId(state.puzzleId);
    if (profile != null) {
      try {
        ledger = const TurtleSoupHintReasoningBridge().apply(
          ledger:
              ledger ?? PublicReasoningLedger(profileVersion: profile.version),
          profile: profile,
          publishedHint: hint,
          messageId: message.id,
          turn: state.questionCount,
        );
      } catch (_) {
        // Optional reasoning metadata must never prevent publishing a hint.
      }
    }
    final next = state.copyWith(
      usedHintCount: state.usedHintCount + 1,
      reasoningLedger: ledger,
    );
    return GameResult.success([
      GameEvent(type: GameEventType.stateChanged, state: next),
      GameEvent(type: GameEventType.messageAdded, message: message),
    ]);
  }

  Future<GameResult<List<GameEvent>>> _reveal(
    GameSession session,
    TurtleSoupState state, {
    required bool solved,
    String actor = 'system',
  }) async {
    final response = await _renderHostResponse(
      session,
      state,
      actor: actor,
      kind: 'reveal',
      content: '',
      semantic: GameHostSemanticResult(
        type: GameHostSemanticType.reveal,
        canonicalText: state.truth,
      ),
      truthMayBeRevealed: true,
    );
    final next = state.copyWith(
      phase: TurtleSoupPhase.revealed,
      isSolved: solved,
      finishedAt: DateTime.now(),
    );
    return GameResult.success([
      GameEvent(type: GameEventType.stateChanged, state: next),
      GameEvent(
        type: GameEventType.messageAdded,
        message: _message(
          session,
          GameMessageType.reveal,
          response.$1,
          id: response.$2,
        ),
      ),
      GameEvent(type: GameEventType.gameFinished, state: next),
    ]);
  }

  bool _containsAny(String input, List<String> keywords) =>
      keywords.any((word) => input.contains(word.toLowerCase()));

  bool _leaksTruth(String visible, TurtleSoupState state) {
    final normalized = visible.replaceAll(RegExp(r'\s+'), '');
    final truth = state.truth.replaceAll(RegExp(r'\s+'), '');
    return normalized.length >= 8 &&
        (truth.contains(normalized) || normalized.contains(truth));
  }

  GameMessage _message(
    GameSession session,
    GameMessageType type,
    String content, {
    String sender = 'host',
    String? id,
  }) => GameMessage(
    id: id,
    sessionId: session.sessionId,
    senderId: sender,
    type: type,
    content: content,
  );

  @override
  Future<GameResult<GameSession>> restore(GameSession session) async =>
      session.gameState is TurtleSoupState
      ? GameResult.success(session)
      : const GameResult(GameResultCode.invalidState, message: '存档状态不完整。');

  @override
  Future<GameResult<List<GameEvent>>> handleCharacterAction(
    GameSession session,
    GameAction action,
  ) async {
    final participant = session.participants
        .where(
          (item) =>
              item.participantId == action.actorParticipantId &&
              item.type == GameParticipantType.character,
        )
        .firstOrNull;
    final state = session.gameState;
    if (participant == null || state is! TurtleSoupState) {
      return const GameResult(
        GameResultCode.invalidAction,
        message: '角色玩家已不在当前房间。',
      );
    }
    final typeName = action.payload['characterAction']?.toString();
    final type = CharacterGameActionType.values
        .where((item) => item.name == typeName)
        .firstOrNull;
    final allowed = const TurtleSoupCharacterParticipationAdapter()
        .allowedActions(session, participant);
    if (action.type != GameActionType.custom ||
        action.payload['kind'] != 'characterGameAction' ||
        type == null ||
        !allowed.contains(type)) {
      return const GameResult(
        GameResultCode.invalidState,
        message: '当前阶段不允许角色这样行动。',
      );
    }
    final text = action.payload['text']?.toString().trim() ?? '';
    switch (type) {
      case CharacterGameActionType.askQuestion:
        if (text.isEmpty) return _emptyInput();
        return _question(session, state, text, participant.participantId);
      case CharacterGameActionType.makeGuess:
        if (text.isEmpty) return _emptyInput();
        return _guess(session, state, text, participant.participantId);
      case CharacterGameActionType.react:
        if (text.isEmpty) return _emptyInput();
        return GameResult.success([
          GameEvent(
            type: GameEventType.messageAdded,
            message: _message(
              session,
              GameMessageType.participant,
              text,
              sender: participant.participantId,
            ),
          ),
        ]);
      case CharacterGameActionType.pass:
        return GameResult.success(const []);
    }
  }

  @override
  Future<GameResult<List<GameEvent>>> advance(GameSession session) async =>
      GameResult.success(const []);
  @override
  Future<GameResult<List<GameEvent>>> pause(GameSession session) async =>
      GameResult.success(const [GameEvent(type: GameEventType.gamePaused)]);
  @override
  Future<GameResult<List<GameEvent>>> resume(GameSession session) async =>
      GameResult.success(const [GameEvent(type: GameEventType.stateChanged)]);
  @override
  Future<GameResult<List<GameEvent>>> finish(GameSession session) async {
    final state = session.gameState;
    return state is TurtleSoupState
        ? await _reveal(session, state, solved: state.isSolved)
        : const GameResult(GameResultCode.invalidState);
  }
}
