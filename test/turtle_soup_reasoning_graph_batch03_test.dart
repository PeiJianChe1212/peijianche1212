import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/participation/character_game_action.dart';
import 'package:peijianche_app/games/registry/mini_game_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_engine.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_logic_profile.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_models.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_profile_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_puzzle_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_reasoning_ledger.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_reasoning_reducer.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_semantic_decision.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_semantic_judge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MiniGameRegistry.instance;

  final profile = _profile();
  final reducer = const TurtleSoupReasoningReducer();
  PublicReasoningLedger empty() => PublicReasoningLedger(profileVersion: 1);
  TurtleSoupSemanticDecision decision(
    TurtleSoupJudgment judgment,
    List<BoundaryEffect> effects,
  ) => TurtleSoupSemanticDecision(judgment: judgment, effects: effects);
  PublicReasoningLedger reduce(
    PublicReasoningLedger current,
    TurtleSoupSemanticDecision semantic, {
    int turn = 1,
    List<String> provenance = const ['q1', 'a1'],
  }) => reducer.reduce(
    current: current,
    decision: semantic,
    question: '公开问题',
    canonicalAnswer: semantic.judgment.canonicalText,
    provenanceMessageIds: provenance,
    currentTurn: turn,
    profile: profile,
  );

  group('pure reducer', () {
    test('empty ledger confirms a fact using approved public text', () {
      final next = reduce(
        empty(),
        decision(TurtleSoupJudgment.yes, const [
          BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f01'),
        ]),
      );
      expect(next.confirmedFacts.single.opaqueRef, 'f01');
      expect(next.confirmedFacts.single.publicText, '设备工作正常。');
      expect(next.confirmedFacts.single.publicText, isNot(contains('隐藏')));
    });

    test('partial upgrades to confirmed and confirmed never downgrades', () {
      final partial = reduce(
        empty(),
        decision(TurtleSoupJudgment.partial, const [
          BoundaryEffect(type: BoundaryEffectType.partialFact, targetId: 'f01'),
        ]),
      );
      final confirmed = reduce(
        partial,
        decision(TurtleSoupJudgment.yes, const [
          BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f01'),
        ]),
        turn: 2,
      );
      final weaker = reduce(
        confirmed,
        decision(TurtleSoupJudgment.partial, const [
          BoundaryEffect(type: BoundaryEffectType.partialFact, targetId: 'f01'),
        ]),
        turn: 3,
      );
      expect(confirmed.partialFacts, isEmpty);
      expect(weaker.confirmedFacts, hasLength(1));
      expect(weaker.partialFacts, isEmpty);
    });

    test('repeated confirmation is idempotent and merges provenance', () {
      final first = reduce(
        empty(),
        decision(TurtleSoupJudgment.yes, const [
          BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f01'),
        ]),
      );
      final second = reduce(
        first,
        decision(TurtleSoupJudgment.no, const [
          BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f01'),
        ]),
        turn: 2,
        provenance: const ['q2', 'a2', 'q1'],
      );
      expect(second.confirmedFacts, hasLength(1));
      expect(second.confirmedFacts.single.provenanceMessageIds, [
        'q1',
        'a1',
        'q2',
        'a2',
      ]);
      expect(second.confirmedFacts.single.updatedAtTurn, 2);
    });

    test('resolves edge and rejects then exhausts misconception', () {
      final next = reduce(
        empty(),
        decision(TurtleSoupJudgment.no, const [
          BoundaryEffect(type: BoundaryEffectType.resolveEdge, targetId: 'e01'),
          BoundaryEffect(
            type: BoundaryEffectType.rejectDirection,
            targetId: 'd02',
          ),
        ]),
      );
      expect(next.resolvedEdges.single.publicText, '正常设备解释了公开现象。');
      expect(next.rejectedDirections.single.publicText, '设备故障已被排除。');
      expect(next.exhaustedDirections.single.opaqueRef, 'd02');
    });

    test('misconception with related partial state is not exhausted', () {
      final current = empty().copyWith(
        partialFacts: const [
          ReasoningLedgerEntry(
            opaqueRef: 'f01',
            publicText: '设备工作正常。',
            provenanceMessageIds: ['q0'],
            updatedAtTurn: 0,
          ),
        ],
      );
      final next = reduce(
        current,
        decision(TurtleSoupJudgment.no, const [
          BoundaryEffect(
            type: BoundaryEffectType.rejectDirection,
            targetId: 'd02',
          ),
        ]),
      );
      expect(next.rejectedDirections, hasLength(1));
      expect(next.exhaustedDirections, isEmpty);
    });

    test(
      'valid branch exhausts only after critical facts and edge resolve',
      () {
        final incomplete = reduce(
          empty(),
          decision(TurtleSoupJudgment.yes, const [
            BoundaryEffect(
              type: BoundaryEffectType.confirmFact,
              targetId: 'f01',
            ),
          ]),
        );
        expect(incomplete.exhaustedDirections, isEmpty);

        final complete = reduce(
          incomplete,
          decision(TurtleSoupJudgment.yes, const [
            BoundaryEffect(
              type: BoundaryEffectType.confirmFact,
              targetId: 'f02',
            ),
            BoundaryEffect(
              type: BoundaryEffectType.resolveEdge,
              targetId: 'e01',
            ),
          ]),
          turn: 2,
        );
        expect(
          complete.exhaustedDirections.map((item) => item.opaqueRef),
          contains('d01'),
        );
      },
    );

    test('empty or sanitized illegal effects do not mutate ledger', () {
      final current = empty();
      final noEffects = reduce(
        current,
        const TurtleSoupSemanticDecision(judgment: TurtleSoupJudgment.yes),
      );
      final pilot = TurtleSoupProfileRegistry.findByPuzzleId(
        'sealed_lunchbox',
      )!;
      final sanitized = parseTurtleSoupSemanticDecision(
        '{"judgment":"yes","effects":[{"type":"confirmFact","ref":"f99"}]}',
        pilot,
      )!;
      final sanitizedResult = const TurtleSoupReasoningReducer().reduce(
        current: PublicReasoningLedger(profileVersion: pilot.version),
        decision: sanitized,
        question: '非法引用',
        canonicalAnswer: '是的。',
        provenanceMessageIds: const ['q1', 'a1'],
        currentTurn: 1,
        profile: pilot,
      );
      expect(identical(noEffects, current), isTrue);
      expect(
        sanitizedResult.toJson(),
        PublicReasoningLedger(profileVersion: 1).toJson(),
      );
    });

    test('public projection strips refs and hidden profile text', () {
      final next = reduce(
        empty(),
        decision(TurtleSoupJudgment.yes, const [
          BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f01'),
        ]),
      );
      final encoded = next.toPublicView().toJson().toString();
      expect(encoded, isNot(contains('f01')));
      expect(encoded, isNot(contains('隐藏事实')));
      expect(encoded, contains('设备工作正常'));
    });
  });

  group('state persistence and engine integration', () {
    test('reasoning ledger round-trips exactly through TurtleSoupState', () {
      final ledger = reduce(
        empty(),
        decision(TurtleSoupJudgment.yes, const [
          BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f01'),
        ]),
      );
      final state = _state(
        TurtleSoupPuzzleRegistry.byId('sealed_lunchbox'),
        ledger: ledger,
      );
      final restored = TurtleSoupState.fromJson(state.toJson());
      expect(restored.reasoningLedger?.toJson(), ledger.toJson());
    });

    test('old state without ledger restores without replay', () {
      final puzzle = TurtleSoupPuzzleRegistry.byId('sealed_lunchbox');
      final json = _state(puzzle).toJson()..remove('reasoningLedger');
      final restored = TurtleSoupState.fromJson(json);
      expect(restored.reasoningLedger, isNull);
      expect(restored.questionCount, 0);
    });

    test(
      'new profiled session starts empty; unprofiled starts without ledger',
      () async {
        final engine = const TurtleSoupEngine();
        final profiled = await engine.initializeSession(
          _baseSession('sealed_lunchbox'),
        );
        final legacy = await engine.initializeSession(
          _baseSession('silent_alarm'),
        );
        final profiledState = profiled.value!.gameState as TurtleSoupState;
        final legacyState = legacy.value!.gameState as TurtleSoupState;
        expect(profiledState.reasoningLedger, isNotNull);
        expect(profiledState.reasoningLedger!.confirmedFacts, isEmpty);
        expect(legacyState.reasoningLedger, isNull);
      },
    );

    test('user and character questions update the same ledger path', () async {
      final semantic = const TurtleSoupSemanticDecision(
        judgment: TurtleSoupJudgment.yes,
        effects: [
          BoundaryEffect(type: BoundaryEffectType.confirmFact, targetId: 'f01'),
        ],
      );
      final engine = TurtleSoupEngine(semanticJudge: _DecisionJudge(semantic));
      final puzzle = TurtleSoupPuzzleRegistry.byId('sealed_lunchbox');
      final initial = _session(puzzle, withCharacter: true);
      final user = await engine.handleUserAction(initial, _ask('用户新问题'));
      final userState = user.value!.first.state! as TurtleSoupState;
      final afterUser = _applyEvents(initial, user.value!);
      final character = await engine.handleCharacterAction(
        afterUser,
        const CharacterGameAction(
          actorParticipantId: 'character:c1',
          type: CharacterGameActionType.askQuestion,
          content: '角色新问题',
        ).toEngineAction(),
      );
      final characterState = character.value!.first.state! as TurtleSoupState;

      expect(userState.reasoningLedger!.confirmedFacts, hasLength(1));
      expect(characterState.reasoningLedger!.confirmedFacts, hasLength(1));
      final entry = characterState.reasoningLedger!.confirmedFacts.single;
      expect(entry.provenanceMessageIds, hasLength(4));
      expect(entry.updatedAtTurn, 2);
    });

    test('play again never carries the previous ledger', () async {
      final puzzle = TurtleSoupPuzzleRegistry.byId('sealed_lunchbox');
      final oldLedger = PublicReasoningLedger(
        profileVersion: 1,
        confirmedFacts: const [
          ReasoningLedgerEntry(
            opaqueRef: 'f01',
            publicText: '旧局结论',
            provenanceMessageIds: ['old'],
            updatedAtTurn: 7,
          ),
        ],
      );
      final session = _session(puzzle).copyWith(
        status: GameSessionStatus.finished,
        gameState: _state(
          puzzle,
          ledger: oldLedger,
          phase: TurtleSoupPhase.finished,
        ),
      );
      final replayed = await const TurtleSoupEngine().playAgain(session);
      final state = replayed.value!.gameState as TurtleSoupState;
      expect(state.reasoningLedger?.confirmedFacts ?? const [], isEmpty);
      expect(
        state.reasoningLedger?.toJson().toString() ?? '',
        isNot(contains('旧局结论')),
      );
    });

    test('legacy puzzle question behavior remains ledger-free', () async {
      final puzzle = TurtleSoupPuzzleRegistry.byId('silent_alarm');
      final result = await TurtleSoupEngine(
        semanticJudge: _LegacyJudge(TurtleSoupJudgment.no),
      ).handleUserAction(_session(puzzle), _ask('无关键词问题'));
      final state = result.value!.first.state! as TurtleSoupState;
      expect(state.reasoningLedger, isNull);
      expect(result.value!.last.message!.content, '不是。');
    });
  });
}

TurtleSoupLogicProfile _profile() => const TurtleSoupLogicProfile(
  version: 1,
  puzzleId: 'test_profile',
  facts: [
    PuzzleFact(
      id: 'f01',
      statement: '隐藏事实：设备本身正常。',
      publicSummary: '设备工作正常。',
      importance: PuzzleFactImportance.critical,
      category: '设备',
    ),
    PuzzleFact(
      id: 'f02',
      statement: '隐藏事实：正常设备造成了现象。',
      publicSummary: '该现象由正常设备造成。',
      importance: PuzzleFactImportance.critical,
      category: '因果',
    ),
  ],
  causalEdges: [
    CausalEdge(
      id: 'e01',
      sourceFactIds: ['f01'],
      relation: CausalRelation.causes,
      targetFactId: 'f02',
      publicSummary: '正常设备解释了公开现象。',
      requiredForSolve: true,
    ),
  ],
  directions: [
    ReasoningDirection(
      id: 'd01',
      hiddenDescription: '调查设备正常运作的完整因果。',
      publicActiveSummary: '继续确认设备状态与公开现象的关系。',
      publicRejectedSummary: '设备运作方向已经充分确认。',
      publicSufficientSummary: '设备状态与公开现象的关系已经足够清楚。',
      relatedFactIds: ['f01', 'f02'],
      sufficiencyFactIds: ['f01', 'f02'],
      sufficiencyEdgeIds: ['e01'],
      kind: ReasoningDirectionKind.validBranch,
    ),
    ReasoningDirection(
      id: 'd02',
      hiddenDescription: '错误认为设备故障。',
      publicRejectedSummary: '设备故障已被排除。',
      relatedFactIds: ['f01'],
      kind: ReasoningDirectionKind.misconception,
    ),
  ],
  boundaryGuides: [],
  solveCriteria: SolveCriteria(
    requiredFactIds: ['f01', 'f02'],
    requiredEdgeIds: ['e01'],
  ),
);

TurtleSoupState _state(
  TurtleSoupPuzzle puzzle, {
  PublicReasoningLedger? ledger,
  TurtleSoupPhase phase = TurtleSoupPhase.questioning,
}) => TurtleSoupState(
  puzzleId: puzzle.id,
  title: puzzle.title,
  surface: puzzle.surface,
  truth: puzzle.truth,
  hints: puzzle.hints,
  phase: phase,
  reasoningLedger: ledger,
);

GameSession _baseSession(String puzzleId) => GameSession(
  sessionId: 'base-$puzzleId',
  gameId: MiniGameRegistry.turtleSoupId,
  createdAt: DateTime(2026, 9, 22),
  updatedAt: DateTime(2026, 9, 22),
  status: GameSessionStatus.ready,
  host: const GameHost.system(),
  participants: const [
    GameParticipant(
      participantId: 'user:1',
      type: GameParticipantType.user,
      displayName: '我',
    ),
  ],
  gameState: BaseGameState(participantState: {'puzzleId': puzzleId}),
);

GameSession _session(TurtleSoupPuzzle puzzle, {bool withCharacter = false}) =>
    GameSession(
      sessionId: 'batch03-${puzzle.id}',
      gameId: MiniGameRegistry.turtleSoupId,
      createdAt: DateTime(2026, 9, 22),
      updatedAt: DateTime(2026, 9, 22),
      status: GameSessionStatus.playing,
      host: const GameHost.system(),
      participants: [
        const GameParticipant(
          participantId: 'user:1',
          type: GameParticipantType.user,
          displayName: '我',
        ),
        if (withCharacter)
          const GameParticipant(
            participantId: 'character:c1',
            type: GameParticipantType.character,
            displayName: '角色一',
            characterId: 'c1',
          ),
      ],
      gameState: _state(
        puzzle,
        ledger: TurtleSoupProfileRegistry.findByPuzzleId(puzzle.id) == null
            ? null
            : PublicReasoningLedger(
                profileVersion: TurtleSoupProfileRegistry.findByPuzzleId(
                  puzzle.id,
                )!.version,
              ),
      ),
    );

GameAction _ask(String text) => GameAction(
  type: GameActionType.custom,
  actorParticipantId: 'user:1',
  payload: {'kind': 'question', 'text': text},
);

GameSession _applyEvents(GameSession session, List<GameEvent> events) {
  var state = session.gameState;
  final messages = [...session.messages];
  for (final event in events) {
    state = event.state ?? state;
    if (event.message != null) messages.add(event.message!);
  }
  return session.copyWith(gameState: state, messages: messages);
}

class _DecisionJudge
    implements TurtleSoupSemanticJudge, TurtleSoupSemanticDecisionJudge {
  _DecisionJudge(this.decision);
  final TurtleSoupSemanticDecision decision;

  @override
  Future<TurtleSoupJudgment?> judge(TurtleSoupJudgeRequest request) async =>
      decision.judgment;

  @override
  Future<TurtleSoupSemanticDecision?> judgeDecision(
    TurtleSoupJudgeRequest request,
    TurtleSoupLogicProfile profile,
  ) async => decision;
}

class _LegacyJudge implements TurtleSoupSemanticJudge {
  _LegacyJudge(this.judgment);
  final TurtleSoupJudgment judgment;

  @override
  Future<TurtleSoupJudgment?> judge(TurtleSoupJudgeRequest request) async =>
      judgment;
}
