import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/games/models/game_models.dart';
import 'package:peijianche_app/games/participation/character_game_action.dart';
import 'package:peijianche_app/games/participation/character_game_agent_view.dart';
import 'package:peijianche_app/games/participation/character_participation_director.dart';
import 'package:peijianche_app/games/registry/mini_game_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_character_agent_view_builder.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_character_participation_adapter.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_engine.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_models.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_profile_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_puzzle_registry.dart';
import 'package:peijianche_app/games/turtle_soup/turtle_soup_reasoning_ledger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MiniGameRegistry.instance;
  const builder = TurtleSoupCharacterAgentViewBuilder();
  const allowed = {
    CharacterGameActionType.askQuestion,
    CharacterGameActionType.makeGuess,
    CharacterGameActionType.react,
    CharacterGameActionType.pass,
  };
  const actor = GameParticipant(
    participantId: 'character:b',
    type: GameParticipantType.character,
    displayName: '角色 B',
    characterId: 'b',
  );

  group('Ledger reasoning context selection', () {
    test(
      'profiled session with Ledger uses authoritative public projection',
      () {
        final session = _session(
          'sealed_lunchbox',
          ledger: _ledger(),
          messages: _conflictingTimeline(),
        );
        final view = builder.build(
          session: session,
          actor: actor,
          allowedActions: allowed,
        );
        final context = view.reasoningContext;
        expect(context.authoritativePublicLedger, isTrue);
        expect(context.recentConfirmedDirections, [
          '同层压力传感器当时正在维护，无法提供正常提示。',
          '压力传感器维护期间，盒盖现象成为研究员确认问题的依据。',
        ]);
        expect(context.recentRejectedDirections, ['研究员不是通过正常工作的压力传感器收到报警。']);
        expect(context.recentPartialDirections, isEmpty);
        expect(context.exhaustedDirections, ['研究员不是通过正常工作的压力传感器收到报警。']);
        expect(
          context.recentConfirmedDirections.join(),
          isNot(contains('Timeline 声称设备坏了')),
        );
      },
    );

    test('unprofiled puzzle keeps heuristic fallback', () {
      final view = builder.build(
        session: _session(
          'silent_alarm',
          messages: _heuristicTimeline('警报与声音有关吗？', '不是。'),
        ),
        actor: actor,
        allowedActions: allowed,
      );
      expect(view.reasoningContext.authoritativePublicLedger, isFalse);
      expect(
        view.reasoningContext.recentRejectedDirections.join(),
        contains('警报与声音有关吗'),
      );
    });

    test('profiled legacy state without Ledger keeps heuristic fallback', () {
      final view = builder.build(
        session: _session(
          'sealed_lunchbox',
          messages: _heuristicTimeline('午餐盒被打开了吗？', '不是。'),
        ),
        actor: actor,
        allowedActions: allowed,
      );
      expect(view.reasoningContext.authoritativePublicLedger, isFalse);
      expect(
        view.reasoningContext.recentRejectedDirections.join(),
        contains('午餐盒被打开了吗'),
      );
    });

    test(
      'recent public Timeline remains available without overriding Ledger',
      () {
        final view = builder.build(
          session: _session(
            'sealed_lunchbox',
            ledger: _ledger(),
            messages: _conflictingTimeline(),
          ),
          actor: actor,
          allowedActions: allowed,
        );
        expect(
          view.visibleHistory.map((message) => message.content),
          contains('Timeline 声称设备坏了吗？'),
        );
        expect(
          view.reasoningContext.recentCharacterQuestions,
          contains('Timeline 声称设备坏了吗？'),
        );
        expect(view.reasoningContext.recentGuesses, contains('最近的一次公开猜测'));
      },
    );

    test('Character-facing prompt contains no refs or hidden profile data', () {
      final profile = TurtleSoupProfileRegistry.findByPuzzleId(
        'sealed_lunchbox',
      )!;
      final view = builder.build(
        session: _session('sealed_lunchbox', ledger: _ledger()),
        actor: actor,
        allowedActions: allowed,
      );
      final prompt = view.toPromptText();
      for (final ref in ['f01', 'f04', 'e01', 'd04']) {
        expect(prompt, isNot(contains(ref)));
      }
      for (final fact in profile.facts) {
        expect(prompt, isNot(contains(fact.statement)));
      }
      for (final direction in profile.directions) {
        expect(prompt, isNot(contains(direction.hiddenDescription)));
      }
      expect(prompt, contains('Public Reasoning Ledger（公开推理记事板，可能不完整）'));
      expect(prompt, contains('已充分探索'));
    });
  });

  test(
    'Character A Engine update is visible to Character B in the same round',
    () async {
      final recording = _RoundAgent();
      final director = CharacterParticipationDirector(
        agent: recording,
        legality: const TurtleSoupCharacterParticipationAdapter(),
        viewBuilder: builder,
      );
      var session = _session(
        'sealed_lunchbox',
        ledger: PublicReasoningLedger(profileVersion: 1),
      );
      var round = director.startRound(session);

      final first = await director.offerTurn(
        session: session,
        trigger: null,
        round: round,
      );
      expect(first.hasAction, isTrue);
      final engineResult = await const TurtleSoupEngine().handleCharacterAction(
        session,
        first.action!.toEngineAction(),
      );
      session = _applyEvents(session, engineResult.value!);
      round = round.advance();

      await director.offerTurn(session: session, trigger: null, round: round);
      expect(recording.views, hasLength(2));
      final second = recording.views.last;
      expect(second.reasoningContext.authoritativePublicLedger, isTrue);
      expect(
        second.reasoningContext.recentConfirmedDirections,
        isNot(contains('同层压力传感器当时正在维护，无法提供正常提示。')),
      );
      expect(
        second.reasoningContext.recentRejectedDirections,
        contains('研究员不是通过正常工作的压力传感器收到报警。'),
      );
      expect(
        second.reasoningContext.currentlyExploredTopics,
        isNot(contains('传感器故障')),
      );
      expect(
        second.visibleHistory.map((message) => message.content),
        contains('研究员是否由正常工作的压力传感器直接获知异常'),
      );
    },
  );
}

PublicReasoningLedger _ledger() => PublicReasoningLedger(
  profileVersion: 1,
  confirmedFacts: const [
    ReasoningLedgerEntry(
      opaqueRef: 'f04',
      publicText: '同层压力传感器当时正在维护，无法提供正常提示。',
      provenanceMessageIds: ['q1', 'a1'],
      updatedAtTurn: 1,
    ),
  ],
  partialFacts: const [
    ReasoningLedgerEntry(
      opaqueRef: 'f02',
      publicText: '楼内换气系统异常造成了持续负压。',
      provenanceMessageIds: ['q2', 'a2'],
      updatedAtTurn: 2,
    ),
  ],
  rejectedDirections: const [
    ReasoningLedgerEntry(
      opaqueRef: 'd04',
      publicText: '研究员不是通过正常工作的压力传感器收到报警。',
      provenanceMessageIds: ['q1', 'a1'],
      updatedAtTurn: 1,
    ),
  ],
  resolvedEdges: const [
    ReasoningLedgerEntry(
      opaqueRef: 'e03',
      publicText: '压力传感器维护期间，盒盖现象成为研究员确认问题的依据。',
      provenanceMessageIds: ['q3', 'a3'],
      updatedAtTurn: 3,
    ),
  ],
  exhaustedDirections: const [
    ReasoningLedgerEntry(
      opaqueRef: 'd04',
      publicText: '研究员不是通过正常工作的压力传感器收到报警。',
      provenanceMessageIds: ['q1', 'a1'],
      updatedAtTurn: 1,
    ),
  ],
);

GameSession _session(
  String puzzleId, {
  PublicReasoningLedger? ledger,
  List<GameMessage> messages = const [],
}) {
  final puzzle = TurtleSoupPuzzleRegistry.byId(puzzleId);
  return GameSession(
    sessionId: 'batch04-$puzzleId',
    gameId: MiniGameRegistry.turtleSoupId,
    createdAt: DateTime(2026, 9, 22),
    updatedAt: DateTime(2026, 9, 22),
    status: GameSessionStatus.playing,
    host: const GameHost.system(),
    participants: const [
      GameParticipant(
        participantId: 'user:1',
        type: GameParticipantType.user,
        displayName: '我',
      ),
      GameParticipant(
        participantId: 'character:a',
        type: GameParticipantType.character,
        displayName: '角色 A',
        characterId: 'a',
      ),
      GameParticipant(
        participantId: 'character:b',
        type: GameParticipantType.character,
        displayName: '角色 B',
        characterId: 'b',
      ),
    ],
    gameState: TurtleSoupState(
      puzzleId: puzzle.id,
      title: puzzle.title,
      surface: puzzle.surface,
      truth: puzzle.truth,
      hints: puzzle.hints,
      phase: TurtleSoupPhase.questioning,
      reasoningLedger: ledger,
    ),
    messages: messages,
  );
}

List<GameMessage> _heuristicTimeline(String question, String answer) => [
  GameMessage(
    id: 'heuristic-question',
    sessionId: 'history',
    senderId: 'character:a',
    type: GameMessageType.question,
    content: question,
  ),
  GameMessage(
    id: 'heuristic-answer',
    sessionId: 'history',
    senderId: 'host',
    type: GameMessageType.answer,
    content: answer,
  ),
];

List<GameMessage> _conflictingTimeline() => [
  ..._heuristicTimeline('Timeline 声称设备坏了吗？', '是的。'),
  GameMessage(
    id: 'recent-guess',
    sessionId: 'history',
    senderId: 'user:1',
    type: GameMessageType.guess,
    content: '最近的一次公开猜测',
  ),
];

GameSession _applyEvents(GameSession session, List<GameEvent> events) {
  var state = session.gameState;
  final messages = [...session.messages];
  for (final event in events) {
    state = event.state ?? state;
    if (event.message != null) messages.add(event.message!);
  }
  return session.copyWith(gameState: state, messages: messages);
}

class _RoundAgent implements CharacterGameAgent {
  final views = <CharacterGameAgentView>[];

  @override
  Future<CharacterGameAction> decide(CharacterGameAgentRequest request) async {
    views.add(request.view);
    if (request.actorParticipantId == 'character:a') {
      return const CharacterGameAction(
        actorParticipantId: 'character:a',
        type: CharacterGameActionType.askQuestion,
        content: '研究员是否由正常工作的压力传感器直接获知异常',
      );
    }
    return CharacterGameAction(
      actorParticipantId: request.actorParticipantId,
      type: CharacterGameActionType.pass,
    );
  }
}
